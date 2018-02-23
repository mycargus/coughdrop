module Async
  extend ActiveSupport::Concern

  include BoyBand::AsyncInstanceMethods
  
  module ClassMethods
    include BoyBand::AsyncClassMethods
  end
end