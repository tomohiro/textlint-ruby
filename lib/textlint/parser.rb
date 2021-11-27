# frozen_string_literal: true

require 'ripper'

module Textlint
  class Parser
    class RubyToTextlintAST < ::Ripper::Filter
      # @param src [String]
      # @param lines [Array<String>]
      def initialize(src)
        super(src)
        @src = src
        @pos = 0
        @lines = @src.lines
      end

      private

      # NOTE: Instance variables are allowed to assign only here to readable code.
      def on_default(event, token, node)
        @token = token

        method_name = :"custom_#{event}"

        if respond_to?(method_name, true)
          @range = @pos...(@pos + @token.size)
          @raw = @src[@range]
          node = send(method_name, node)
        end

        @pos += @token.size

        node
      end

      def default_node_attributes(type:, **attributes)
        {
          type: type,
          raw: @raw,
          range: @range,
          loc: Textlint::Nodes::TxtNodeLineLocation.new(
            start: Textlint::Nodes::TxtNodePosition.new(
              line: lineno,
              column: column
            ),
            end: end_txt_node_position
          )
        }.merge(attributes)
      end

      def custom_on_tstring_content(parentNode)
        node = Textlint::Nodes::TxtTextNode.new(
          **default_node_attributes(
            type: Textlint::Nodes::STR,
            value: @token
          )
        )

        parentNode.children.push(node)

        parentNode
      end

      def end_txt_node_position
        break_count = @token.scan(Textlint::BREAK_RE).size

        last_column = if break_count == 0
                        column + @token.size
                      else
                        @token.match(LAST_LINE_RE).to_s.size
                      end

        Textlint::Nodes::TxtNodePosition.new(
          line: lineno + break_count,
          column: last_column
        )
      end
    end

    # Parse ruby code to AST for textlint
    #
    # @param src [String]
    #
    # @return [Textlint::Nodes::TxtParentNode]
    def self.parse(src)
      new(src).call
    end

    # @param src [String] ruby source code
    def initialize(src)
      @src = src
    end

    # Parse ruby code to AST for textlint
    #
    # @return [Textlint::Nodes::TxtParentNode]
    def call
      check_syntax!

      document = Textlint::Nodes::TxtParentNode.new(
        type: Textlint::Nodes::DOCUMENT,
        raw: @src,
        range: 0...@src.size,
        loc: Textlint::Nodes::TxtNodeLineLocation.new(
          start: Textlint::Nodes::TxtNodePosition.new(
            line: 1,
            column: 0
          ),
          end: Textlint::Nodes::TxtNodePosition.new(
            line: @src.split(Textlint::BREAK_RE).size + 1,
            column: @src.match(LAST_LINE_RE).to_s.size # extract last line
          )
        )
      )

      RubyToTextlintAST.new(@src).parse(document)
    end

    private

    def check_syntax!
      RubyVM::InstructionSequence.compile(@src)
    rescue ::SyntaxError => error
      raise Textlint::SyntaxError, error.message
    end
  end
end
