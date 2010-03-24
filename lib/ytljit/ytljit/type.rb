module YTLJit

  module Type
    class TypeCommon
    end

    class Scalar<TypeCommon
      def initialize(size, align = 4, kind = :int)
        @size = size
        @alignment = align
        @kind = kind
      end
      
      attr :size
      attr :alignment
    end

    class PointedData<TypeCommon
      def initialize(type, index)
        @type = type
        @index = index
      end

      attr :type
      attr :index

      def size
        @reftype.size
      end

      def alignment
        @reftype.alignment
      end
    end
    
    class Pointer<TypeCommon
        def initialize(type)
          @type = type
        end
      
      def size
        4
      end
      
      def alignment
        4
      end
      
      attr :type

      def [](n = 0)
        PointedData.new(@reftype, n)
      end
    end
    
    @@type_table = {}
    def self.deftype(name, tinfo)
      type = Scalar.new(*tinfo)
      const_set(name.to_s.upcase, type)
      @@type_table[name] = type
    end
    
    def self.type_table
      @@type_table
    end
    
    deftype :void, [0, 1]
    deftype :int8, [1, 1]
    deftype :sint8, [1, 1]
    deftype :uint8, [1, 1]
    deftype :int16, [2, 2]
    deftype :uint16, [2, 2]
    deftype :int32, [4, 4]
    deftype :uint32, [4, 4]
    deftype :int64, [8, 8]
    deftype :uint64, [8, 8]
  end
end