class CompilationEngine
  Token = Struct.new(:type, :value)

  KEYWORD = :KEYWORD
  SYMBOL = :SYMBOL
  IDENTIFIER = :IDENTIFIER
  INT_CONST = :INT_CONST
  STRING_CONST = :STRING_CONST

  # keywordConstant: 'true' | 'false' | 'null' | 'this'
  KEYWORD_CONSTANTS = ["true", "false", "null", "this"].freeze

  # op: '+' | '-' | '*' | '/' | '&' | '|' | '<' | '>' | '='
  OPS = ["+", "-", "*", "/", "&", "|", "<", ">", "="].freeze

  # unaryOP: '-' | '~'
  UNARY_OPS = ["-", "~"].freeze

  def initialize(tokenizer, symbol_table, vm_writer)
    @symbol_table = symbol_table
    @vm_writer = vm_writer

    @tokens = []
    while tokenizer.has_more_tokens
      tokenizer.advance
      @tokens << read_token(tokenizer)
    end

    @pos = 0
    @class_name = nil
    @label_index = 0
    @current_subroutine_kind = nil
    @current_subroutine_name = nil
  end

  def close
    @vm_writer.close
  end

  # class: 'class' className '{' classVarDec* subroutineDec* '}'
  def compile_class
    write_keyword("class")
    @class_name = write_identifier
    write_symbol("{")

    while keyword?("static") || keyword?("field")
      compile_class_var_dec
    end

    while keyword?("constructor") || keyword?("function") || keyword?("method")
      compile_subroutine_dec
    end

    write_symbol("}")
  end

  # classVarDec: ('static' | 'field') type varName (',' varName)* ';'
  def compile_class_var_dec
    kind = write_keyword
    type = compile_type

    name = write_identifier
    @symbol_table.define(name:, type:, kind:)

    while symbol?(",")
      write_symbol(",")
      name = write_identifier
      @symbol_table.define(name:, type:, kind:)
    end

    write_symbol(";")
  end

  # subroutineDec: ('constructor' | 'function' | 'method') ('void' | type) subroutineName '(' parameterList ')' subroutineBody
  def compile_subroutine_dec
    @symbol_table.reset

    @current_subroutine_kind = write_keyword

    if keyword?("void")
      write_keyword("void")
    else
      compile_type
    end

    @current_subroutine_name = write_identifier
    write_symbol("(")

    if @current_subroutine_kind == "method"
      @symbol_table.define(name: "this", type: @class_name, kind: "argument")
    end

    compile_parameter_list
    write_symbol(")")
    compile_subroutine_body
  end

  # parameterList: ((type varName) (',' type varName)*)?
  def compile_parameter_list
    if !symbol?(")")
      type = compile_type
      name = write_identifier
      @symbol_table.define(name:, type:, kind: "argument")

      while symbol?(",")
        write_symbol(",")
        type = compile_type
        name = write_identifier
        @symbol_table.define(name:, type:, kind: "argument")
      end
    end
  end

  # subroutineBody: '{' varDec* statements '}'
  def compile_subroutine_body
    write_symbol("{")

    while keyword?("var")
      compile_var_dec
    end

    n_vars = @symbol_table.var_count(kind: "var")
    @vm_writer.write_function(name: "#{@class_name}.#{@current_subroutine_name}", nVars: n_vars)

    if @current_subroutine_kind == "constructor"
      n_fields = @symbol_table.var_count(kind: "field")
      @vm_writer.write_push(segment: "constant", index: n_fields)
      @vm_writer.write_call(name: "Memory.alloc", nArgs: 1)
      @vm_writer.write_pop(segment: "pointer", index: 0)
    elsif @current_subroutine_kind == "method"
      @vm_writer.write_push(segment: "argument", index: 0)
      @vm_writer.write_pop(segment: "pointer", index: 0)
    end

    compile_statements
    write_symbol("}")
  end

  # varDec: 'var' type varName(',' varName)* ';'
  def compile_var_dec
    write_keyword("var")
    type = compile_type

    name = write_identifier
    @symbol_table.define(name:, type:, kind: "var")

    while symbol?(",")
      write_symbol(",")
      name = write_identifier
      @symbol_table.define(name:, type:, kind: "var")
    end

    write_symbol(";")
  end

  # statements: statement*
  # statement: letStatement | ifStatement | whileStatement | doStatement | returnStatement
  def compile_statements
    while keyword?("let") || keyword?("if") || keyword?("while") || keyword?("do") || keyword?("return")
      if keyword?("let")
        compileLet
      elsif keyword?("if")
        compileIf
      elsif keyword?("while")
        compileWhile
      elsif keyword?("do")
        compileDo
      else
        compileReturn
      end
    end
  end

  # letStatement: 'let' varName ('[' expression ']')? '=' expression ';'
  def compileLet
    write_keyword("let")
    name = write_identifier

    if symbol?("[")
      push_variable(name)
      write_symbol("[")
      compileExpression
      write_symbol("]")
      @vm_writer.write_arithmetic(command: "add")

      write_symbol("=")
      compileExpression
      @vm_writer.write_pop(segment: "temp", index: 0)
      @vm_writer.write_pop(segment: "pointer", index: 1)
      @vm_writer.write_push(segment: "temp", index: 0)
      @vm_writer.write_pop(segment: "that", index: 0)
    else
      write_symbol("=")
      compileExpression
      pop_variable(name)
    end

    write_symbol(";")
  end

  # ifStatement: 'if' '(' expression ')' '{' statements '}' ('else' '{' statements '}')?
  def compileIf
    false_label = next_label("IF_FALSE")
    end_label = next_label("IF_END")

    write_keyword("if")
    write_symbol("(")
    compileExpression
    write_symbol(")")
    @vm_writer.write_arithmetic(command: "not")
    @vm_writer.write_if(label: false_label)

    write_symbol("{")
    compile_statements
    write_symbol("}")

    if keyword?("else")
      @vm_writer.write_goto(label: end_label)
      @vm_writer.write_label(label: false_label)

      write_keyword("else")
      write_symbol("{")
      compile_statements
      write_symbol("}")
      @vm_writer.write_label(label: end_label)
    else
      @vm_writer.write_label(label: false_label)
    end

  end

  # whileStatement: 'while' '(' expression ')' '{' statements '}'
  def compileWhile
    exp_label = next_label("WHILE_EXP")
    end_label = next_label("WHILE_END")

    @vm_writer.write_label(label: exp_label)
    write_keyword("while")
    write_symbol("(")
    compileExpression
    write_symbol(")")
    @vm_writer.write_arithmetic(command: "not")
    @vm_writer.write_if(label: end_label)

    write_symbol("{")
    compile_statements
    write_symbol("}")

    @vm_writer.write_goto(label: exp_label)
    @vm_writer.write_label(label: end_label)
  end

  # doStatement: 'do' subroutineCall ';'
  def compileDo
    write_keyword("do")
    compile_subroutine_call
    write_symbol(";")
    @vm_writer.write_pop(segment: "temp", index: 0)
  end

  # returnStatement: 'return' expression? ';'
  def compileReturn
    write_keyword("return")
    if symbol?(";")
      @vm_writer.write_push(segment: "constant", index: 0)
    else
      compileExpression
    end
    write_symbol(";")
    @vm_writer.write_return
  end

  # expression: term (op term)*
  def compileExpression
    compileTerm
    while current_token && current_token.type == SYMBOL && OPS.include?(current_token.value)
      op = write_symbol
      compileTerm
      write_binary_op(op)
    end
  end

  # term: integerConstant | stringConstant | keywordConstant | varName |
  #       varName '[' expression ']' | '(' expression ')' | unaryOp term | subroutineCall
  def compileTerm

    if current_token.type == INT_CONST
      value = write_integer_constant
      @vm_writer.write_push(segment: "constant", index: value)
    elsif current_token.type == STRING_CONST
      value = write_string_constant
      write_string_constant_vm(value)
    elsif KEYWORD_CONSTANTS.include?(current_token.value)
      keyword = write_keyword
      write_keyword_constant_vm(keyword)
    elsif current_token.type == IDENTIFIER
      if next_token && next_token.type == SYMBOL && next_token.value == "["
        name = write_identifier
        push_variable(name)
        write_symbol("[")
        compileExpression
        write_symbol("]")
        @vm_writer.write_arithmetic(command: "add")
        @vm_writer.write_pop(segment: "pointer", index: 1)
        @vm_writer.write_push(segment: "that", index: 0)
      elsif next_token && next_token.type == SYMBOL && (next_token.value == "(" || next_token.value == ".")
        compile_subroutine_call
      else
        name = write_identifier
        push_variable(name)
      end
    elsif current_token.type == SYMBOL && current_token.value == "("
      write_symbol("(")
      compileExpression
      write_symbol(")")
    elsif current_token.type == SYMBOL && UNARY_OPS.include?(current_token.value)
      op = write_symbol
      compileTerm
      write_unary_op(op)
    else
      raise "Unexpected term token: #{current_token.type} #{current_token.value.inspect}"
    end

  end

  # expressionList: (expression(',' expression)*)?
  def compileExpressionList
    count = 0
    unless symbol?(")")
      compileExpression
      count += 1
      while symbol?(",")
        write_symbol(",")
        compileExpression
        count += 1
      end
    end
    count
  end

  private

    # tokenizerからトークンを解析し、Tokenオブジェクトを生成する
    def read_token(tokenizer)
      type = tokenizer.token_type
      value =
        case type
        when KEYWORD
          tokenizer.keyword.to_s.downcase
        when SYMBOL
          tokenizer.symbol
        when IDENTIFIER
          tokenizer.identifier
        when INT_CONST
          tokenizer.int_val.to_s
        when STRING_CONST
          tokenizer.string_val
        else
          raise "Unknown token type: #{type.inspect}"
        end
      Token.new(type, value)
    end

    def current_token
      @tokens[@pos]
    end

    def next_token
      @tokens[@pos + 1]
    end

    def keyword?(keyword = nil)
      token = current_token
      return false unless token && token.type == KEYWORD
      return true if keyword.nil?

      token.value == keyword
    end

    def symbol?(symbol = nil)
      token = current_token
      return false unless token && token.type == SYMBOL
      return true if symbol.nil?

      token.value == symbol
    end

    def write_identifier(expected = nil)
      token = current_token
      value = write_token(token, IDENTIFIER)
      if expected && value != expected
        raise "Expected identifier #{expected.inspect}, got #{value.inspect}"
      end
      @pos += 1
      value
    end

    def write_symbol(expected = nil)
      token = current_token
      value = write_token(token, SYMBOL)
      if expected && value != expected
        raise "Expected symbol #{expected.inspect}, got #{value.inspect}"
      end
      @pos += 1
      value
    end

    def write_keyword(expected = nil)
      token = current_token
      value = write_token(token, KEYWORD)
      if expected && value != expected
        raise "Expected keyword #{expected.inspect}, got #{value.inspect}"
      end
      @pos += 1
      value
    end

    def write_integer_constant
      token = current_token
      value = write_token(token, INT_CONST)
      @pos += 1
      value.to_i
    end

    def write_string_constant
      token = current_token
      value = write_token(token, STRING_CONST)
      @pos += 1
      value
    end

    # type: 'int' | 'char' | 'boolean' | className
    def compile_type
      if keyword?("int") || keyword?("char") || keyword?("boolean")
        write_keyword
      else
        write_identifier
      end
    end

    # subroutineCall:
    #   subroutineName '(' expressionList ')' |
    #   (className | varName) '.' subroutineName '(' expressionList ')'
    def compile_subroutine_call
      receiver = write_identifier
      n_args = 0
      call_name = nil

      if symbol?(".")
        write_symbol(".")
        subroutine_name = write_identifier
        kind = @symbol_table.kind_of(name: receiver)
        if kind == "none"
          call_name = "#{receiver}.#{subroutine_name}"
        else
          type = @symbol_table.type_of(name: receiver)
          push_variable(receiver)
          n_args += 1
          call_name = "#{type}.#{subroutine_name}"
        end
      else
        # this.method() の省略記法
        @vm_writer.write_push(segment: "pointer", index: 0)
        n_args += 1
        call_name = "#{@class_name}.#{receiver}"
      end

      write_symbol("(")
      n_args += compileExpressionList
      write_symbol(")")
      @vm_writer.write_call(name: call_name, nArgs: n_args)
    end

    def write_binary_op(op)
      case op
      when "+"
        @vm_writer.write_arithmetic(command: "add")
      when "-"
        @vm_writer.write_arithmetic(command: "sub")
      when "*"
        @vm_writer.write_call(name: "Math.multiply", nArgs: 2)
      when "/"
        @vm_writer.write_call(name: "Math.divide", nArgs: 2)
      when "&"
        @vm_writer.write_arithmetic(command: "and")
      when "|"
        @vm_writer.write_arithmetic(command: "or")
      when "<"
        @vm_writer.write_arithmetic(command: "lt")
      when ">"
        @vm_writer.write_arithmetic(command: "gt")
      when "="
        @vm_writer.write_arithmetic(command: "eq")
      else
        raise "Unsupported binary op: #{op.inspect}"
      end
    end

    def write_unary_op(op)
      case op
      when "-"
        @vm_writer.write_arithmetic(command: "neg")
      when "~"
        @vm_writer.write_arithmetic(command: "not")
      else
        raise "Unsupported unary op: #{op.inspect}"
      end
    end

    def write_keyword_constant_vm(keyword)
      case keyword
      when "true"
        @vm_writer.write_push(segment: "constant", index: 0)
        @vm_writer.write_arithmetic(command: "not")
      when "false", "null"
        @vm_writer.write_push(segment: "constant", index: 0)
      when "this"
        @vm_writer.write_push(segment: "pointer", index: 0)
      else
        raise "Unsupported keyword constant: #{keyword.inspect}"
      end
    end

    def write_string_constant_vm(value)
      @vm_writer.write_push(segment: "constant", index: value.length)
      @vm_writer.write_call(name: "String.new", nArgs: 1)
      value.each_byte do |byte|
        @vm_writer.write_push(segment: "constant", index: byte)
        @vm_writer.write_call(name: "String.appendChar", nArgs: 2)
      end
    end

    def segment_and_index_for(name)
      kind = @symbol_table.kind_of(name:)
      index = @symbol_table.index_of(name:)

      case kind
      when "static"
        ["static", index]
      when "field"
        ["this", index]
      when "argument"
        ["argument", index]
      when "var"
        ["local", index]
      else
        raise "Undefined variable: #{name}"
      end
    end

    def push_variable(name)
      segment, index = segment_and_index_for(name)
      @vm_writer.write_push(segment:, index:)
    end

    def pop_variable(name)
      segment, index = segment_and_index_for(name)
      @vm_writer.write_pop(segment:, index:)
    end

    def write_token(token, tag)
      raise "Unexpected end of tokens while expecting #{tag}" if token.nil?
      raise "Token type mismatch. expected=#{tag} actual=#{token.type}" unless token.type == tag

      token.value
    end

    def next_label(prefix)
      label = "#{prefix}_#{@label_index}"
      @label_index += 1
      label
    end
end
