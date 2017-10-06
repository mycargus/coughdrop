require 'permissable'

module Permissions
  extend ActiveSupport::Concern
  include Permissable::InstanceMethods
  
  module ClassMethods
    include Permissable::ClassMethods
  end
end