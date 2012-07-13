class Cache

  attr_reader :store, :max_keys

  def initialize(max_keys = 1000)
    @store = {}
    @max_keys = max_keys
  end

  def get(key)
    store[key]
  end

  def set(key, value)
    return if store[key] == value
    pop if store.length > max_keys
    store[key] = value
  end

  def pop
    store.delete(store.keys.last)
  end

  def show
    store.each { |k,v| puts "#{k} -> #{v}" }; nil
  end

end
