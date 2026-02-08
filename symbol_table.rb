class SymbolTable
  def initialize
    @class_table = {}
    @subroutine_table = {}

    @static_index = -1
    @field_index = -1
    @argument_index = -1
    @var_index = -1
  end

  # restメソッドはサブルーチン宣言のコンパイルを開始する時に呼び出すため、
  # subroutineテーブルとstatic, fieldのインデックスのみを初期化している。
  def reset
    @subroutine_table = {}
    @argument_index = -1
    @var_index = -1
  end

  def define(name:, type:, kind:)
    index = case kind
    when "static"
      @static_index += 1
      @static_index
    when "field"
      @field_index += 1
      @field_index
    when "argument"
      @argument_index += 1
      @argument_index
    when "var"
      @var_index += 1
      @var_index
    else
      raise "不正なkindです。"
    end

    table = (kind == "static" || kind == "field") ? @class_table : @subroutine_table
    table[name] = {type:, kind:, index:}
  end

  def var_count(kind:)
    case kind
    when "static"
      @static_index + 1
    when "field"
      @field_index + 1
    when "argument"
      @argument_index + 1
    when "var"
      @var_index + 1
    else
      raise "不正なkindです。"
    end
  end

  def kind_of(name:)
    entry = @subroutine_table[name] || @class_table[name]
    if entry.nil?
      "none"
    else
      entry[:kind]
    end
  end

  def type_of(name:)
    entry = @subroutine_table[name] || @class_table[name]
    return nil if entry.nil?
    entry[:type]
  end

  def index_of(name:)
    entry = @subroutine_table[name] || @class_table[name]
    return nil if entry.nil?
    entry[:index]
  end
end
