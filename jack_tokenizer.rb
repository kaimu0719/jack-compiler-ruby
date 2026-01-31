class JackTokenizer
  # Jackプログラミング言語の使用では、トークンは5つのタイプに分類される。
  # キーワード(keyword): class, while, ...
  # シンボル(symbol): +, <, ...
  # 整数定数(integerConstant): 17, 314, ...
  # 文字列定数(stringConstant): "FAQ" や "Frequently Asked Question"
  # 識別子(identifier): 変数、クラス、サブルーチンの名前付けに使用されるテキストラベル
  KEYWORD      = :KEYWORD
  SYMBOL       = :SYMBOL
  INT_CONST    = :INT_CONST
  STRING_CONST = :STRING_CONST
  IDENTIFIER   = :IDENTIFIER

  KEYWORDS = %w[
    class method function constructor
    int boolean char void
    var static field
    let do if else while return
    true false null this
  ].freeze

  SYMBOLS = "{}()[].,;+-*/&|<>=~".chars.freeze

  def initialize(file_path)
    source = File.read(file_path)
    source = remove_comments(source)

    @source = source
    @index = 0

    @current_token = nil
    @current_type  = nil
  end

  def has_more_tokens
    skip_whitespace
    @index < @source.length
  end

  def advance
    raise "advance called but no more tokens" unless has_more_tokens

    # トークナイザーが現在見ている「1文字」を表している
    ch = @source[@index]

    # 文字列定数であるか？
    # JackのstringConstantは必ず"で始まるから
    # ch == '"'が true であれば トークンが stringConstantであることを確認できる
    if ch == '"'
      # 現在の stringConstant のトークンを取得する
      # 例えば、"\"HELLO WORLD\"" という文字列がある場合、
      # @current_token = "HELLO WORLD" を取り出すことができる。
      @current_token = read_string_constant
      @current_type  = STRING_CONST

    elsif SYMBOLS.include?(ch)
      @current_token = ch
      @current_type  = SYMBOL
      @index += 1

      # digit?メソッドで ch が数字の0~9かどうかを判定する
    elsif digit?(ch)
      @current_token = read_integer_constant
      @current_type  = INT_CONST

      # 先頭文字列を見て、identifier か keyword
      # かどうかを判定している。
    elsif ident_start?(ch)
      # keywordまたはidentifierの値を取得する
      word = read_identifier_like

      if KEYWORDS.include?(word)
        @current_token = word
        @current_type  = KEYWORD
      else
        @current_token = word
        @current_type  = IDENTIFIER
      end
    else
      raise "Unexpected character at index #{@index}: #{ch.inspect}"
    end

    nil
  end

  def token_type
    raise "No current token. Call advance first." if @current_token.nil?
    @current_type
  end

  def keyword
    ensure_type!(KEYWORD)
    @current_token.upcase.to_sym
  end

  def symbol
    ensure_type!(SYMBOL)
    @current_token
  end

  def identifier
    ensure_type!(IDENTIFIER)
    @current_token
  end

  def int_val
    ensure_type!(INT_CONST)
    @current_token.to_i
  end

  def string_val
    ensure_type!(STRING_CONST)
    @current_token
  end

  private

    def remove_comments(source)
      source = source.gsub(%r{/\*.*?\*/}m, "")
      source = source.gsub(%r{//.*$}, "")
      source
    end

    def skip_whitespace
      while @index < @source.length
        ch = @source[@index]
        break unless ch == " " || ch == "\n" || ch == "\t" || ch == "\r"
        @index += 1
      end
    end

    def read_string_constant
      # 開始の`"`を読み捨てる
      # stringの中身だけを取り出したい
      start = @index + 1

      # stringの最後の`"`のインデックスを取得する
      closing = @source.index('"', start)
      raise "Unterminated string constant" unless closing

      # ここで`"`を除いた文字列本体を取り出す
      content = @source[start...closing]

      # Tokenizerは「読む＝indexを進める」
      @index = closing + 1
      content
    end

    def read_integer_constant
      start = @index
      while @index < @source.length && digit?(@source[@index])
        @index += 1
      end
      @source[start...@index]
    end

    def read_identifier_like
      start = @index
      @index += 1
      while @index < @source.length && ident_part?(@source[@index])
        @index += 1
      end
      @source[start...@index]
    end

    def digit?(ch)
      # chはstringであるため、0~9かどうかをチェックしたい場合は、
      # 文字列コード(Unicode/ASCII)で比較する必要がある。
      ch >= "0" && ch <= "9"
    end

    # identifierは
    # 先頭文字列が「英字」または「_」
    # 2文字目以降が英字・数字・_
    # → 数字では始めることはできない。
    # そのため「先頭の判定」と「2文字目以降の判定」を分けている
    # ident_start?, ident_part?
    def ident_start?(ch)
      # まず大文字アルファベットかどうかを判定
      # 次に小文字アルファベットかどうかを判定
      # 最後に_かどうかを判定
      (ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z") || ch == "_"
    end

    # ch が 識別子(identifier)の途中で使えるか？
    # 識別子の途中で使える条件が
    # - 英字（大文字・小文字）
    # - _
    # - 数字
    def ident_part?(ch)
      # ident_start?で 英字(大文字・小文字)または_かどうかを判定し
      # digit?で数字かどうかを判定している
      ident_start?(ch) || digit?(ch)
    end

    def ensure_type!(expected)
      raise "No current token. Call advance first." if @current_token.nil?
    
      actual = @current_type
      raise "tokenType mismatch. expected=#{expected} actual=#{actual}" unless actual == expected
    end
end
