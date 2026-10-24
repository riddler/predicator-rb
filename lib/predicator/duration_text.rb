# frozen_string_literal: true

module Predicator
  # A duration as text in the language's duration-literal grammar, both
  # ways, as the reference writes and reads it.
  #
  # Written, the units come largest first, each as its amount and its
  # suffix (`y`, `mo`, `w`, `d`, `h`, `m`, `s`, `ms`); a unit that is not
  # positive is left out, and a duration with nothing left to write is
  # `0s`.
  #
  # Read, the whole text is one or more components, each digits, an
  # optional fraction (a point and digits) and a suffix, with no sign, no
  # space and no empty text; `mo` and `ms` are read before `m`. A repeated
  # unit adds to what came before. A fraction is exact or refused: it is
  # worth a whole number of milliseconds (a month 30 days, a year 365) or
  # the text is not a duration, and that remainder is spent largest first
  # through days, hours, minutes, seconds and milliseconds only, the whole
  # part keeping its own unit.
  #
  # The module holds no state. It is private to the package.
  module DurationText
    # Each unit's suffix and its worth in milliseconds, largest unit first.
    UNITS = {
      years: ["y", 31_536_000_000], months: ["mo", 2_592_000_000], weeks: ["w", 604_800_000],
      days: ["d", 86_400_000], hours: ["h", 3_600_000], minutes: ["m", 60_000], seconds: ["s", 1000],
      milliseconds: ["ms", 1]
    }.freeze

    # The unit each suffix names.
    SUFFIXES = UNITS.to_h { |unit, (suffix, _)| [suffix, unit] }.freeze

    # The units a fraction's remainder is spent into.
    REMAINDER_UNITS = %i[days hours minutes seconds milliseconds].freeze

    # One component, and the whole text as a run of them.
    COMPONENT = /([0-9]+)(?:\.([0-9]+))?(mo|ms|y|w|d|h|m|s)/
    TEXT = /\A(?:[0-9]+(?:\.[0-9]+)?(?:mo|ms|y|w|d|h|m|s))+\z/

    module_function

    # @param duration [Duration]
    # @return [String]
    def write(duration)
      parts = UNITS.filter_map do |unit, (suffix, _)|
        amount = duration.public_send(unit)
        "#{amount}#{suffix}" if amount.positive?
      end
      parts.empty? ? "0s" : parts.join
    end

    # @param text [String]
    # @return [Duration, nil] the duration the text names, or nil when it
    #   names none
    def read(text)
      return unless TEXT.match?(text)

      pairs = text.scan(COMPONENT).map { |whole, fraction, suffix| component(whole, fraction, suffix) }
      return if pairs.include?(nil)

      units = Hash.new(0)
      pairs.flatten(1).each { |unit, amount| units[unit] += amount }
      Duration.new(**units)
    end

    # The unit pairs one component is worth, or nil when its fraction is not
    # a whole number of milliseconds.
    def component(whole, fraction, suffix)
      whole = Integer(whole, 10)
      unit = SUFFIXES.fetch(suffix)
      fraction ? expand(whole, fraction, unit) : [[unit, whole]]
    end

    # The unit pairs a component with a fraction is worth, or nil when the
    # fraction is not a whole number of milliseconds.
    def expand(whole, fraction, unit)
      worth = Integer(fraction, 10) * UNITS.fetch(unit).last
      remainder, inexact = worth.divmod(10**fraction.size)
      return unless inexact.zero?

      [[unit, whole], *spend(remainder)]
    end

    def spend(milliseconds)
      REMAINDER_UNITS.filter_map do |unit|
        amount, milliseconds = milliseconds.divmod(UNITS.fetch(unit).last)
        [unit, amount] if amount.positive?
      end
    end
  end
  private_constant :DurationText
end
