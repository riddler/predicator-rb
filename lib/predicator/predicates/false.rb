module Predicator
  module Predicates
    class False
      def satisfied? context=Predicator::Context.new
        false
      end

      def == other
        other.kind_of?(self.class)
      end
    end
  end
end