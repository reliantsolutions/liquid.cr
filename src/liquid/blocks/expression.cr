require "./block"
require "../filters"
require "../context"
require "../regex"

module Liquid::Block
  abstract class AbstractExpression < Node
  end

  class Filtered < AbstractExpression
    getter filters, first
    @first : Expression
    @filters : Array(Tuple(Filters::Filter, Array(Expression)?))

    def initialize(str)
      if match = str.match GFILTERED
        @first = Expression.new match["first"]
        @filters = Array(Tuple(Filters::Filter, Array(Expression)?)).new
        matches = str.scan GFILTER
        if matches.first["filter"] == match["first"] || "\"#{matches.first["filter"]}\"" == match["first"]
          matches.shift
        end

        matches.each do |fm|
          if filter = Filters::FilterRegister.get fm["filter"]
            args : Array(Expression)?
            args = nil
            if (margs = fm["args"]?)
              args = Array(Expression).new
              splitted = margs.split(',').map &.strip
              splitted.each { |m| args << Expression.new(m) }
            end
            @filters << {filter, args}
          else
            raise InvalidExpression.new "Filter #{fm["filter"]} is not registered."
          end
        end
      else
        raise InvalidExpression.new "Invalid filter use :#{str}"
      end
    end
  end

  class Boolean < AbstractExpression
    getter inner
    @inner : Bool

    def initialize(str)
      if match(str)
        @inner = str == "true"
      else
        raise Exception.new "Invalid Boolean expression : #{str}"
      end
    end

    def match(str : String) : Regex::MatchData?
      str.match /^false$|^true$/
    end
  end

  class Expression < AbstractExpression
    @var : String

    def initialize(var)
      @var = var.strip
      pre_cache
    end

    def pre_cache
      @children << Boolean.new @var if @var == "true" || @var == "false"
      if m = @var.match GSTRING
        @children << Raw.new m["str"]
      end
      if @var.match intern(FILTERED)
        @children << Filtered.new @var
      end
    end

    private def intern(re)
      /^#{re}$/
    end

    def eval(data) : Any
      ret = if @var == "true" || @var == "false"
              @var == "true"
            elsif m = @var.match GSTRING
              m["str"]
            elsif m = @var.match intern(GINT)
              m["intval"].to_i
            elsif m = @var.match intern(GFLOAT)
              m["floatval"].to_f32
            elsif @var.match intern(VAR)
              data.get(@var)
            elsif m = @var.match intern(GCMP)
              le = Expression.new(m["left"]).eval data
              re = Expression.new(m["right"]).eval data
              BinOperator.process m["op"], le, re
            elsif m = @var.scan MULTIPLE_EXPR
              stack = [] of Expression | BoolOperator
              m.each do |match|
                stack << BoolOperator.new match["op"] if match["op"]?
                stack << Expression.new match["expr"]
              end
              BoolOperator.process stack, data
            else
              raise InvalidExpression.new "Invalid Expression : #{@var}"
            end

      if ret.is_a? Any
        ret
      else
        Any.new ret
      end
    end
  end
end
