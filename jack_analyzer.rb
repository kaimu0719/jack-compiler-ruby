require_relative "jack_tokenizer"
require_relative "compilation_engine"
require_relative "symbol_table"
require_relative "vm_writer"

class JackAnalyzer
  def initialize(input_path)
    @input_path = input_path
  end

  def analyze
    files = jack_files_from(@input_path)

    files.each do |file|
      tokenizer = JackTokenizer.new(file)
      symbol_table = SymbolTable.new
      out_path = output_path_for(file)
      vm_writer = VmWriter.new(out_path)
      engine = CompilationEngine.new(tokenizer, symbol_table, vm_writer)
      engine.compile_class
      engine.close
    end
  end

  private

    def jack_files_from(path)
      if File.directory?(path)
        Dir.glob(File.join(path, "*.jack")).sort
      else
        [path]
      end
    end

    def output_path_for(input_path)
      base = File.basename(input_path, ".jack")
      File.join(File.dirname(input_path), "#{base}.vm")
    end
end
