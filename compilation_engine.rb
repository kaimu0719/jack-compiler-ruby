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

  XML_TAG = {
    KEYWORD      => "keyword",
    SYMBOL       => "symbol",
    IDENTIFIER   => "identifier",
    INT_CONST    => "integerConstant",
    STRING_CONST => "stringConstant"
  }.freeze


  def initialize(tokenizer, output_path)
    @tokens = []
    while tokenizer.has_more_tokens
      tokenizer.advance
      @tokens << read_token(tokenizer)
    end

    @pos = 0
    @indent = 0
    @out = File.open(output_path, "w")
  end

  def close
    @out.close
  end

  # class 'class': className '{' classVarDec* subroutineDec* '}'
  def compileClass
    open_tag("class")
    write_keyword
    write_identifier
    write_symbol

    # トークンがkeywordの'static'または'field'であれば、
    # プログラム構造が classVarDec であると判断できる。
    while keyword?("static") || keyword?("field")
      compileClassVarDec
    end

    # トークンがkeywordの'constructor', 'function', 'method'であれば、
    # プログラム構造が subroutineDec であると判断できる。
    while keyword?("constructor") || keyword?("function") || keyword?("method")
      compileSubroutineDec
    end
  
    write_symbol
    close_tag("class")
  end

  # スタティック変数の宣言またはフィールド変数の宣言をコンパイルする。
  # classVarDec: ('static' | 'field') type varName (',' varName)* ';'
  def compileClassVarDec
    open_tag("classVarDec")
    write_keyword
    compile_type
    write_identifier

    while symbol?(",")
      write_symbol
      write_identifier
    end

    write_symbol
    close_tag("classVarDec")
  end

  # メソッド、ファンクション、コンストラクタをコンパイルする。
  # subroutineDec: ('constructor' | 'function' | 'method') ('void' | type) subroutineName
  def compileSubroutineDec
    open_tag("subroutineDec")
    write_keyword

    if keyword?("void")
      write_keyword
    else
      compile_type
    end
    write_identifier
    write_symbol
    compileParameterList
    write_symbol
    compileSubroutineBody
    close_tag("subroutineDec")
  end

  # parameterList: ((type varName) (',' type varName))
  def compileParameterList
    open_tag("parameterList")
    unless symbol?(")")
      compile_type
      write_identifier
      while symbol?(",")
        write_symbol
        compile_type
        write_identifier
      end
    end
    close_tag("parameterList")
  end

  # subroutineBody: '{' varDec* statements '}'
  def compileSubroutineBody
    open_tag("subroutineBody")
    write_symbol
    while keyword?("var")
      compileVarDec
    end
    compileStatements
    write_symbol
    close_tag("subroutineBody")
  end

  # varDec: 'var' type varName(',' varName)* ';'
  def compileVarDec
    open_tag("varDec")
    write_keyword
    compile_type
    write_identifier
    while symbol?(",")
      write_symbol
      write_identifier
    end
    write_symbol
    close_tag("varDec")
  end

  # statements: statement*
  # statement: letStatement | ifStatement | whileStatement | doStatement | returnStatement
  def compileStatements
    open_tag("statements")
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
    close_tag("statements")
  end

  # letStatement: 'let' varName ('[' expression ']')? '=' expression';'
  def compileLet
    open_tag("letStatement")
    write_keyword
    write_identifier
    if symbol?("[")
      write_symbol
      compileExpression
      write_symbol
    end
    write_symbol
    compileExpression
    write_symbol
    close_tag("letStatement")
  end

  # ifStatement: 'if' '(' expression ')' '{' statements '}' ('else' '{' statements '}')?
  def compileIf
    open_tag("ifStatement")
    write_keyword
    write_symbol
    compileExpression
    write_symbol
    write_symbol
    compileStatements
    write_symbol
    if keyword?("else")
      write_keyword
      write_symbol
      compileStatements
      write_symbol
    end
    close_tag("ifStatement")
  end

  # whileStatement: 'while' '(' expression ')' '{' statements '}'
  def compileWhile
    open_tag("whileStatement")
    write_keyword
    write_symbol
    compileExpression
    write_symbol
    write_symbol
    compileStatements
    write_symbol
    close_tag("whileStatement")
  end

  # doStatement: 'do' subroutineCall';'
  def compileDo
    open_tag("doStatement")
    write_keyword
    compile_subroutine_call
    write_symbol
    close_tag("doStatement")
  end

  # returnStatement: 'return' expression?';'
  def compileReturn
    open_tag("returnStatement")
    write_keyword
    unless symbol?(";")
      compileExpression
    end
    write_symbol
    close_tag("returnStatement")
  end

  # expression: term (op term)*
  def compileExpression
    open_tag("expression")
    compileTerm
    while current_token && current_token.type == SYMBOL && OPS.include?(current_token.value)
      write_symbol
      compileTerm
    end
    close_tag("expression")
  end

  # term: integerConstant | stringConstant | keywordConstant | varName |
  #       varName'[' expression ']' | '(' expression ')' | (unaryOp term) | subroutineCall
  def compileTerm
    open_tag("term")
    if current_token.type == INT_CONST
      write_integer_constant
    elsif current_token.type == STRING_CONST
      write_string_constant
    elsif KEYWORD_CONSTANTS.include?(current_token.value)
      write_keyword
    elsif current_token.type == IDENTIFIER
      if next_token && next_token.type == SYMBOL && next_token.value == "["
        write_identifier
        write_symbol
        compileExpression
        write_symbol
      elsif next_token && next_token.type == SYMBOL && (next_token.value == "(" || next_token.value == ".")
        compile_subroutine_call
      else
        write_identifier
      end
    elsif current_token.type == SYMBOL && current_token.value == "("
      write_symbol
      compileExpression
      write_symbol
    elsif current_token.type == SYMBOL && UNARY_OPS.include?(current_token.value)
      write_symbol
      compileTerm
    else
      raise "Unexpected term token: #{current_token.type} #{current_token.value.inspect}"
    end
    close_tag("term")
  end

  # expressionList (expression(',' expression)*)?
  def compileExpressionList
    open_tag("expressionList")
    unless symbol?(")")
      compileExpression
      while symbol?(",")
        write_symbol
        compileExpression
      end
    end
    close_tag("expressionList")
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
      # トークンがkeywordであるかだけを確認したい場合
      return false unless token && token.type == KEYWORD
      return true if keyword.nil?

      # 引数で与えられたトークンが一致しているか
      token.value == keyword
    end

    def symbol?(symbol = nil)
      token = current_token
      # トークンがsymbolであるかだけを確認したい場合
      return false unless token && token.type == SYMBOL
      return true if symbol.nil?

      # 引数で与えられたトークンが一致しているか
      token.value == symbol
    end

    def write_identifier
      token = current_token
      write_token(token, IDENTIFIER)
      @pos += 1
    end

    def write_symbol
      token = current_token
      write_token(token, SYMBOL)
      @pos += 1
    end

    def write_keyword
      token = current_token
      write_token(token, KEYWORD)
      @pos += 1
    end

    def write_integer_constant
      token = current_token
      write_token(token, INT_CONST)
      @pos += 1
    end

    def write_string_constant
      token = current_token
      write_token(token, STRING_CONST)
      @pos += 1
    end

    # type: 'int' | 'char' | 'boolean' | className
    def compile_type
      if keyword?("int") || keyword?("char") || keyword?("boolean")
        write_keyword
      else
        write_identifier
      end
    end

    def compile_subroutine_call
      write_identifier
      if symbol?(".")
        write_symbol
        write_identifier
      end
      write_symbol
      compileExpressionList
      write_symbol
    end

    def write_token(token, tag)
      tag_name = XML_TAG.fetch(tag)
      value = token.value
      value = escape_xml(value) if tag == SYMBOL
      write_line("<#{tag_name}> #{value} </#{tag_name}>")
    end

    def escape_xml(str)
      str.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    # 開始タグを記述する
    def open_tag(name)
      write_line("<#{name}>")
      @indent += 1
    end

    def close_tag(name)
      @indent -= 1
      write_line("</#{name}>")
    end

    def write_line(line)
      @out.puts("#{"  " * @indent}#{line}")
    end
end
