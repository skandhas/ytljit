module YTLJit

  class StepHandler
    case $ruby_platform
    when /x86_64/
      REGS = {
        "RAX" => 0, "RCX" => 2, "RDX" => 3, "RBX" => 4, 
        "RBP" => 5, "RSP" => 16, "RDI" => 6, "RSI" => 7,
        "R8" => 8, "R9" => 9, "R10" => 10, "R11" => 11, "R12" => 12,
        "R13" => 13, "R14" => 14, "R15" => 15
      }

    when /i.86/
      REGS = {
        "EAX" => 0, "ECX" => 2, "EDX" => 3, "EBX" => 4, 
        "EBP" => 5, "ESP" => 8, "EDI" => 6, "ESI" => 7
      }
    end
    
    def step_handler(*regval)
      STDERR.print "#{regval[1].to_s(16)} "
      STDERR.print CodeSpace.disasm_cache[regval[1].to_s(16)], "\n"
      STDERR.print $frame_struct_tab[regval[1]][1].map {|n| n.class}, "\n"
      REGS.each do |rname, no|
        STDERR.print rname
        STDERR.print ": 0x"
        STDERR.print regval[no].to_s(16)
        STDERR.print " "
      end
      STDERR.print "\n"
     end
  end

  class Generator
    def initialize(asm)
      @asm = asm
    end
    attr :asm
  end

  class OutputStream
    def asm=(a)
      @asm = a
    end

    def base_address
      0
    end

    def var_base_address(offset = 0)
      OpVarMemAddress.new(lambda {offset})
    end
  end

  class FileOutputStream<OutputStream
    def initialize(st)
      @stream = st
    end

    def emit(code)
      @stream.write(code)
    end
  end

  class DummyOutputStream<OutputStream
    def initialize(st)
    end

    def emit(code)
    end
  end

  class Assembler
    @@value_table_cache = {}
    @@value_table_entity = ValueSpace.new

    def self.set_value_table(out)
      @@value_table_cache = {}
      @@value_table_entity = out
    end

    def self.get_value_table(out)
      [@@value_table_entity, @@value_table_cache]
    end

    def initialize(out, gen = GeneratorExtend)
      @generator = gen.new(self)
      @output_stream = out
      @retry_mode = false
      @step_mode = false
      @asmsend_history = []

      # Instruction pach table for forwarding reference
      # This is array of proc object.
      @after_patch_tab = []
      @patched_num = 0

      reset
    end

    def reset
      @current_address = @output_stream.base_address
      @offset = 0
      @patched_num = 0
    end

    attr_accessor :current_address
    attr_accessor :step_mode
    attr          :offset
    attr          :output_stream
    attr          :after_patch_tab
    attr          :retry_mode

    def var_current_address
      current_address = @current_address

      func = lambda {
        current_address
      }
      OpVarMemAddress.new(func)
    end

    attr_accessor :generated_code

    def store_outcode(out)
      update_state(out)
      @offset += out.bytesize
      @output_stream.emit(out)
      out
    end

    def update_state(out)
      @current_address += out.bytesize
      out
    end

    def with_retry(&body)
      org_base_address = @output_stream.base_address
      yield

      org_retry_mode = @retry_mode
      @retry_mode = :change_org
      while org_base_address != @output_stream.base_address do
        org_base_address = @output_stream.base_address
        reset
        @output_stream.reset
        @asmsend_history.each do |arg|
          send(arg[0], *arg[1])
        end
        @output_stream.update_refer
      end

      @after_patch_tab[@patched_num..-1].each do |patproc|
        patproc.call
      end
      @patched_num = @after_patch_tab.size
      @retry_mode = org_retry_mode
    end

    def add_value_entry(val)
      off= nil
      unless off = @@value_table_cache[val] then
        off = @@value_table_entity.current_pos
        @@value_table_entity.emit([val.value].pack("Q"))
        @@value_table_cache[val] = off
      end

      @@value_table_entity.var_base_address(off)
    end

    def add_var_value_retry_func(mn, args)
      if args.any? {|e| e.is_a?(OpVarValueMixin) } and 
         @retry_mode == false then
        offset = @offset
        stfunc = lambda {
          with_current_address(@output_stream.base_address + offset) {
            orgretry_mode = @retry_mode
            @retry_mode = :change_op
            out = @generator.send(mn, *args)
            if out.is_a?(Array)
              @output_stream[offset] = out[0]
            else
              @output_stream[offset] = out
            end
            @retry_mode = orgretry_mode
          }
        }
        args.each do |e|
          if e.is_a?(OpVarValueMixin) then
            e.add_refer(stfunc)
          end
        end
      end
    end

    def method_missing(mn, *args)
      out = @generator.call_stephandler
      store_outcode(out)

      if @retry_mode == false then
        case mn
        when :call_with_arg
          args.push(@generator.call_with_arg_get_argsize(*args))
        end
        @asmsend_history.push [mn, args]
      end
        
      add_var_value_retry_func(mn, args)
      out = @generator.send(mn, *args)
      if out.is_a?(Array) then
        store_outcode(out[0])
      else
        store_outcode(out)
      end
      out
    end

    def with_current_address(address)
      org_curret_address = self.current_address
      self.current_address = address
      yield
      self.current_address = org_curret_address
    end
  end
end
