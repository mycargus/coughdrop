require 'bigdecimal'

class BigDecimal
  def as_json(options = nil) #:nodoc:
    if finite?
      self.to_f
    else
      NilClass::AS_JSON
    end
  end
end