class Array
    def each
      return unless block_given?
  
      i = 0
      while i < count
        yield self[i]
        i += 1
      end
  
      self
    end
  
    def each_with_index
      return unless block_given?
  
      i = 0
      while i < count
        yield self[i], i
        i += 1
      end
  
      self
    end
  
    def map!
      return unless block_given?
      
      i = 0
      while i < count
        self[i] = yield self[i]
        i += 1
      end
  
      self
    end
  
    def map
      return unless block_given?
      
      ary = []
      i = 0
      while i < count
        ary[i] = yield self[i]
        i += 1
      end
  
      ary
    end
  
    def first
      self[0] 
    end
  
    def last
      self[count - 1] 
    end
  
    def empty?
      count == 0 
    end
  
    def inspect
      res = ""
      each_with_index do |x, i|
        if i == count - 1
          res += x.inspect
        else
          res += x.inspect + ", "
        end
      end
      
      "[" + res + "]"
    end

    alias :to_s, :inspect
  end