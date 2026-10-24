# frozen_string_literal: true

module Predicator
  module Evaluator
    # The `call` opcode, as the reference's ISA (docs/isa.md, section 5)
    # states it: the handler {Machine} runs for its row of {INSTRUCTIONS}.
    #
    # `call` pops its argument count of values, the deepest first, and pushes
    # what the named function answers. The name is looked up first among the
    # functions the caller passed to this evaluation, then in the package's
    # library ({Library}); nothing else is reachable, and nothing is
    # registered globally.
    #
    # Every refusal is an EvaluationError, and except for too few values on
    # the stack (reason insufficient_arguments) its reason is its message,
    # as the reference writes them:
    #
    # - a name neither holds: `Unknown function: NAME`;
    # - a count of arguments the function does not take:
    #   `Function NAME() expects COUNTS arguments, got N`, where COUNTS is a
    #   count, the counts it takes joined by " or ", or "at least" a count;
    # - a library function refusing its arguments: the library's sentence,
    #   e.g. `len() expects a string argument`;
    # - a function that raises: `Function NAME() raised: ` and the
    #   exception's inspect.
    #
    # A host function is called with a copy of each argument
    # ({Boundary.copy}), so that nothing it does to a list, a map or a
    # String it is handed changes the context or a value the evaluation
    # holds. Its answer is checked against the value domain: one outside it
    # is refused with an EvaluationError carrying the boundary's reason
    # (unsupported_host_value, non_finite_number, cyclic_value or
    # depth_limit_exceeded), and nothing is pushed.
    module Calls
      # How a library function refuses its arguments: the message is the
      # refusal's reason. Raised and rescued inside a call; it never leaves
      # one.
      class Refusal < StandardError; end

      include Library

      # The counts of arguments a host's callable takes, as a Range: its
      # required positional parameters up to those and its optional ones,
      # with no end when it takes a rest parameter. A Proc is read as a
      # lambda would be, so a block's missing arguments are refused rather
      # than read as null.
      def self.counts(callable)
        parameters = parameters_of(callable)
        required = parameters.count { |kind, _| kind == :req }
        return (required..) if parameters.any? { |kind, _| kind == :rest }

        required..(required + parameters.count { |kind, _| kind == :opt })
      end

      def self.parameters_of(callable)
        case callable
        when Proc then callable.parameters(lambda: true)
        when Method then callable.parameters
        else callable.method(:call).parameters
        end
      end
      private_class_method :parameters_of

      private

      # Pops arg_count values, calls the named function with them, first
      # argument deepest, and pushes its answer.
      def call_function(at, name, arg_count)
        if @stack.size < arg_count
          return EvaluationError.new(
            reason: "insufficient_arguments",
            message: "Function #{name}() expects #{arg_count} arguments, but only #{@stack.size} values on stack"
          )
        end

        args = @stack.pop(arg_count)
        answer = dispatch(name, args)
        answer.is_a?(Answered) ? push(at, answer.value) : answer
      end

      # What a call that succeeded answered, kept apart from the error value
      # a refused call answers, since a function may answer any value.
      Answered = Data.define(:value)
      private_constant :Answered

      def dispatch(name, args)
        callable, counts = resolve(name)
        return call_error("Unknown function: #{name}") unless callable
        return call_error(wrong_count(name, counts, args.size)) unless counts.include?(args.size)
        return host_call(name, callable, args) if @functions.key?(name)

        Answered.new(callable.call(*args))
      rescue ClockFault then raise
      rescue Refusal => e
        call_error(e.message)
      rescue StandardError => e
        call_error("Function #{name}() raised: #{e.inspect}")
      end

      # Calls a host function with a copy of each argument, answering its
      # answer, or the refusal of one outside the value domain ({Boundary}).
      def host_call(name, callable, args)
        answer = callable.call(*args.map { |arg| Boundary.copy(arg) })
        Boundary.refusal(answer, "Function #{name}() answered a value that") || Answered.new(answer)
      end

      # The callable a name reaches and the counts of arguments it takes: a
      # host function first, then the library's.
      def resolve(name)
        host = @functions[name]
        return [host, Calls.counts(host)] if host

        entry = Library::FUNCTIONS[name]
        [method(entry.handler), entry.counts] if entry
      end

      def wrong_count(name, counts, given)
        described =
          if counts.end.nil? then "at least #{counts.begin}"
          else counts.to_a.join(" or ")
          end
        "Function #{name}() expects #{described} arguments, got #{given}"
      end

      def call_error(message) = EvaluationError.new(reason: message, message:)
    end
    private_constant :Calls
  end
end
