module Tarantool
  module Request
    class DefaultShardProc
      def call(shard_values, shards_count, this)
        if shard_values.size == 1 && Integer === shard_values[0]
          shard_values[0] % shards_count
        elsif shard_values.all?
          shard_values.hash % shards_count
        end
      end
    end

    class ModuloShardProc
      def call(shard_values, shards_count, this)
        shard_values[0] && shard_values[0] % shards_count
      end
    end

    def _init_shard_vars(shard_proc, init_shard_for_index = true)
      if init_shard_for_index
        @shard_by_index = @index_fields.index{|index| index == @shard_fields}
        @shard_for_index = @index_fields.map{|index|
            if (pos = @shard_fields.map{|name| index.index(name)}).any?
              pos.map{|i| i || 2**30}
            end
        }
        @shard_proc = case shard_proc
                      when nil, :default
                        DefaultShardProc.new
                      when :modulo, :module
                        ModuloShardProc.new
                      else
                        unless shard_proc.respond_to?(:call)
                          raise ArgumentError, "Wrong sharding proc object #{shard_proc.inspect}"
                        end
                        shard_proc
                      end
      end

      @shards_count = @tarantool.shards_count
      @default_shard = 0
    end

    def _detect_shards_for_keys(keys, index_no)
      return _detect_shards_for_key(keys, index_no)  unless Array === keys
      if index_no == @shard_by_index && (
            @index_fields.size == 1 ||
            keys.all?{|key| Array === key && key.size == @index_fields.size}
          )
        _flat_uniq keys.map{|key| detect_shard(key)}
      elsif pos = @shard_for_index[index_no]
        _flat_uniq keys.map{|key| detect_shard([*key].values_at(*pos)) }
      else
        all_shards
      end
    end

    def _detect_shards_for_key(key, index_no)
      if index_no == @shard_by_index
        detect_shard(key)
      elsif pos = @shard_for_index[index_no]
        detect_shard(key.values_at(*pos))
      else
        all_shards
      end
    end

    def _detect_shards(keys)
      _flat_uniq keys.map{|key| detect_shard(key)}
    end

    def _flat_uniq(array)
      hsh = {}
      array.each do |v|
        if v.respond_to?(:each)
          v.each{|vv| hsh[vv] = true}
        else
          hsh[v] = true
        end
      end
      hsh.keys
    end

    # methods for override
    def detect_shard(shard_values)
      shard_values = [shard_values]  unless Array === shard_values
      @shard_proc.call(shard_values, @shards_count, self) || all_shards
    end

    def _get_shard_nums
      @shards_count == 1 ? @default_shard : yield
    end

    def all_shards
      (0...@shards_count).to_a
    end

    def shard(shard_number)
      case shard_number
      when Integer
        if shard_number >= @shards_count
          raise ArgumentError, "There is no shard #{shard_number}, amount of shards is #{@shards_count}"
        end
      when Array
        shard_number.each do|i|
          if i >= @shards_count
            raise ArgumentError, "There is no shard #{i}, amount of shards is #{@shards_count}"
          end
        end
      else
        raise ArgumentError, "Shard number should be integer or array of integers"
      end
      (@_fixed_shards ||= {})[shard_number] ||=
          clone.instance_exec do
            @shards_count = 1
            @default_shard = shard_number
            self
          end
    end
  end
end