require_relative "./jack_tokenizer"

path = ARGV[0]
files = if File.directory?(path)
  Dir.glob(File.join(path, "*.jack")).sort
else
  [path]
end

files.each do |file|
  tokenizer = JackTokenizer.new(file)
  base = File.basename(file, ".jack")
  output_path = File.join(File.dirname(file), "#{base}T.xml")
  out = File.open(output_path, "w")

  out.puts("<tokens>")
  while tokenizer.has_more_tokens
    tokenizer.advance
    type = tokenizer.token_type

    case type
    when JackTokenizer::KEYWORD
      out.puts("<keyword> #{tokenizer.keyword.to_s.downcase} </keyword>")
    when JackTokenizer::SYMBOL
      out.puts("<symbol> #{tokenizer.symbol} </symbol>")
    when JackTokenizer::IDENTIFIER
      out.puts("<identifier> #{tokenizer.identifier} </identifier>")
    when JackTokenizer::INT_CONST
      out.puts("<integerConstant> #{tokenizer.int_val.to_s} </integerConstant>")
    when JackTokenizer::STRING_CONST
      out.puts("<stringConstant> #{tokenizer.string_val} </stringConstant>")
    else
      raise "Unknown token type: #{type.inspect}"
    end
  end
  out.puts("</tokens>")
end
