# == Schema Information
#
# Table name: admin_users
#
#  id                     :integer          not null, primary key
#  osm_id                 :integer
#  oauth_token            :string(255)
#  oauth_secret           :string(255)
#  email                  :string(255)      default(""), not null
#  encrypted_password     :string(255)      default(""), not null
#  reset_password_token   :string(255)
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  sign_in_count          :integer          default(0), not null
#  current_sign_in_at     :datetime
#  last_sign_in_at        :datetime
#  current_sign_in_ip     :string(255)
#  last_sign_in_ip        :string(255)
#  created_at             :datetime
#  updated_at             :datetime
#  osm_username           :string(255)
#  changeset_id           :integer
#  role_id                :integer
#  location               :spatial          point, 4326
#

class AdminUser < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :omniauthable,
         :recoverable, :rememberable, :trackable

  validates :email, uniqueness: { allow_nil: true, allow_blank: true }
  validates :osm_id, presence: true

  has_many :matched_places, class_name: Place, foreign_key: :matcher_id
  has_many :changesets

  belongs_to :role
  before_create :set_default_role

  attr_accessor :address, :use_location

  # By default, use the GEOS implementation for spatial columns.
  self.rgeo_factory_generator = RGeo::Geos.factory_generator

  def self.find_for_osm_oauth(access_token, signed_in_resource=nil)
    data = access_token.info
    if admin_user = AdminUser.where(:osm_id => data.id).first
      # found
    else
      admin_user = AdminUser.create!(:osm_id => data.id, :password => Devise.friendly_token[0, 20])
    end
    admin_user.update_attributes( oauth_token: access_token.credentials.token,
                                  oauth_secret: access_token.credentials.secret,
                                  osm_username: data.display_name
                                )
    admin_user
  end

  def lat
    location.try(:y)
  end

  def lon
    location.try(:x)
  end

  def display_name
    (osm_username || email || osm_id.to_s) +
    " (#{matched_places.count})"
  end

  def oauth_authorized?
    !!(oauth_token && oauth_secret)
  end

  def client
    ::Rosemary::OauthClient.new(access_token)
  end

  def access_token
    if oauth_authorized?
      consumer = OAuth::Consumer.new(OpenStreetMapConfig.oauth_key, OpenStreetMapConfig.oauth_secret, :site => OpenStreetMapConfig.oauth_site)
      access_token = OAuth::AccessToken.new(consumer, oauth_token, oauth_secret)
    end
  end

  def admin?
    role.try(:name) == 'admin'
  end

  private

  def set_default_role
    self.role ||= Role.find_by_name('user') if ActiveRecord::Base.connection.table_exists? 'roles'
  end
end
