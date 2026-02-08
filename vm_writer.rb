class VmWriter
  def initialize(output_path)
    @out = File.open(output_path, "w")
  end

  def write_push(segment:, index:)
    @out.puts("push #{segment} #{index}")
  end                                                                                                                                     

  def write_pop(segment:, index:)
    @out.puts("pop #{segment} #{index}")
  end

  def write_arithmetic(command:)
    @out.puts(command)
  end

  def write_label(label:)
    @out.puts("label #{label}")
  end

  def write_goto(label:)
    @out.puts("goto #{label}")
  end

  def write_if(label:)
    @out.puts("if-goto #{label}")
  end

  def write_call(name:, nArgs:)
    @out.puts("call #{name} #{nArgs}")
  end

  def write_function(name:, nVars:)
    @out.puts("function #{name} #{nVars}")
  end

  def write_return
    @out.puts("return")
  end

  def close
    @out.close
  end
end
