class ModNote < ApplicationRecord
  extend TimeAgoInWords

  belongs_to :moderator,
             :class_name => "User",
             :foreign_key => "moderator_user_id",
             :inverse_of => :moderations
  belongs_to :user

  scope :recent, -> { where('created_at >= ?', 1.week.ago).order('created_at desc') }
  scope :for, ->(user) { includes(:moderator).where('user_id = ?', user).order('created_at desc') }

  validates :note, :markeddown_note, presence: true, length: { maximum: 65_535 }

  delegate :username, to: :user

  def username=(username)
    self.user_id = nil

    if (u = User.find_by(username: username))
      self.user_id = u.id
      @username = u.username
    else
      errors.add(:username, "is not a valid user")
    end
  end

  def note=(n)
    self[:note] = n.to_s.strip
    self.markeddown_note = self.generated_markeddown
  end

  def generated_markeddown
    Markdowner.to_html(self.note)
  end

  def self.create_from_message(message, moderator)
    user = moderator.id == message.recipient.id ? message.author : message.recipient
    ModNote.create!(
      moderator: moderator,
      user: user,
      created_at: message.created_at,
      note: <<~NOTE
        *#{message.author.username} #{message.hat ? message.hat.to_txt : ''}-> #{message.recipient.username}*: #{message.subject}

        #{message.body}
      NOTE
    )
  end

  def self.tattle_on_invited(user, invitation_code)
    invitation = Invitation.find_by(code: invitation_code)
    return unless invitation

    sender = invitation.user
    sender_url = Rails.application.routes.url_helpers.user_url(
      sender,
      host: Rails.application.domain
    )
    ModNote.create!(
      moderator: InactiveUser.inactive_user,
      user: user,
      created_at: Time.current,
      note: "Attempted to redeem invitation code #{invitation.code} while logged in:\n" +
        "- sent by: [#{sender.username}](#{sender_url})\n" +
        "- created_at: #{invitation.created_at}\n" +
        "- used_at: #{invitation.used_at || 'unused'}\n" +
        "- email: #{invitation.email}\n" +
        "- memo: #{invitation.memo}"
    )
  end

  def self.tattle_on_new_user_tagging!(story)
    ModNote.create!(
      moderator: InactiveUser.inactive_user,
      user: story.user,
      created_at: Time.current,
      note: "Attempted to submit a story with tag(s) not allowed to new users:\n" +
        "- user joined: #{time_ago_in_words(story.user.created_at)}\n" +
        "- url: #{story.url}\n" +
        "- title: #{story.title}\n" +
        "- user_is_author: #{story.user_is_author}\n" +
        "- tags: #{story.tags.map(&:tag).join(' ')}\n" +
        "- description: #{story.description}\n"
    )
  end

  def self.tattle_on_story_domain!(story, reason)
    ModNote.create!(
      moderator: InactiveUser.inactive_user,
      user: story.user,
      created_at: Time.current,
      note: "Attempted to post a story from a #{reason} domain:\n" +
        "- user joined: #{time_ago_in_words(story.user.created_at)}\n" +
        "- url: #{story.url}\n" +
        "- title: #{story.title}\n" +
        "- user_is_author: #{story.user_is_author}\n" +
        "- tags: #{story.tags.map(&:tag).join(' ')}\n" +
        "- description: #{story.description}\n"
    )
  end
end
