# OmniCache - An in-memory caching library for Ruby

OmniCache is an in-memory caching library for Ruby. It does not do anything particularly
new or innovative. Rather, it aims to harmonize a variety of features into a single
library that can accomodate a wide range of use cases.

Out of the box, OmniCache is simple, safe, and fast.

OmniCache also supports (via configuration):

- TTLs
- LRU eviction
- Thread-safety
- Count-based size limiting
- Byte-based size limiting
- Customizable serializers

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'omnicache'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install omnicache

## Usage

```ruby
store = OmniCache::Store.new
store.write("key", "value")

store.read("key")
# => "value"

store.write("key", "value", ttl_seconds: 10)
sleep(20)

store.read("key")
# => nil

# keys can be anything, but are coerced to strings
store.write(123, "value")

store.read("123")
# => "value"
```

`[]` and `get` are aliases for `read`.

`[]=` and `set` are aliases for `write` (when `[]=` is used, no TTL can be provided).

## Configuration

OmniCache supports the following configuration options, provided as keyword arguments to the `Store` constructor.

| Option | Default | Description |
| ------ | ------- | ----------- |
| default_ttl_seconds | `nil` | The default TTL for all entries. When a TTL is provided explicitly to `write`, that TTL takes precedence. |
| max_entries | `nil` | The maximum number of entries to store. When this number is exceeded, the least recently used entries are removed. Expired entries are removed before removing any other entries. |
| max_size_bytes | `nil` | The maximum total size of all entries. The size of an entry is the `bytesize` of the key plus the `bytesize` of the value. When this number is exceeded, the least recently used entries are removed. Expired entries are removed before removing any other entries. |
| threadsafe | `true` | Whether or not the store should be threadsafe. Disabling this option may improve performance. |
| serializer | `Marshal` | An object that responds to `dump` (for serialization) and `load` (for desserialization). Setting this option to a no-op serializer may improve performance at the cost of some safety, since values in the store may be mutable outside of the store. When `max_size_bytes` is set, the serializer must produce objects that respond to `bytesize`.

## OmniCache vs Other Caching Libraries

### Feature Comparison

|   | OmniCache | Minicache | LruRedux | FastCache | MemoryStore (ActiveSupport) |
| - | --------- | --------- | -------- | --------- | --------------------------- |
| Entry-specific TTLs | :white_check_mark: | :white_check_mark: | :x: | :x: | :white_check_mark: |
| Default TTLs | :white_check_mark: | :x: | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| Thread-safety | :white_check_mark: | :x: | :white_check_mark: | :x: | :white_check_mark: |
| Count-based size limit | :white_check_mark: | :x: | :white_check_mark: | :white_check_mark: | :x: |
| Byte-based size limit | :white_check_mark: | :x: | :x: | :x: | :white_check_mark: |
| Customizable serializer | :white_check_mark: | :x: | :x: | :x: | :white_check_mark: |

ActiveSupport's `MemoryStore` supports almost all of the same features, but is much slower than `OmniCache`. See the benchmarks below for more detail.

### Benchmarks

Benchmark code can be viewed in the `bin/` folder.

When trading off safety for performance, `OmniCache` is the second fastest cache in the test. Only `LruRedux` fares better. This is because `LruRedux` does not support key-level TTLs, so it does not use entry wrapper objects.

```
100-character string
--------------------

Rehearsal ------------------------------------------------------------------------
OmniCache                              0.216528   0.000702   0.217230 (  0.217311)
OmniCache (non-threadsafe)             0.206778   0.000694   0.207472 (  0.207497)
OmniCache (identity, non-threadsafe)   0.112577   0.000468   0.113045 (  0.113106)
MiniCache                              0.119772   0.000435   0.120207 (  0.120257)
LruRedux                               0.065857   0.000239   0.066096 (  0.066099)
FastCache                              0.232569   0.004727   0.237296 (  0.237306)
MemoryStore                            0.997803   0.005275   1.003078 (  1.003120)
--------------------------------------------------------------- total: 1.964424sec

                                           user     system      total        real
OmniCache                              0.237444   0.000737   0.238181 (  0.238187)
OmniCache (non-threadsafe)             0.229418   0.000739   0.230157 (  0.230156)
OmniCache (identity, non-threadsafe)   0.120902   0.000340   0.121242 (  0.121336)
MiniCache                              0.130030   0.000491   0.130521 (  0.130559)
LruRedux                               0.064644   0.001132   0.065776 (  0.065782)
FastCache                              0.367464   0.005032   0.372496 (  0.372489)
MemoryStore                            1.206926   0.005267   1.212193 (  1.212468)


Array of 10 UUIDs
-----------------

Rehearsal ------------------------------------------------------------------------
OmniCache                              0.821787   0.005903   0.827690 (  0.827921)
OmniCache (non-threadsafe)             0.725825   0.006205   0.732030 (  0.732049)
OmniCache (identity, non-threadsafe)   0.115646   0.000491   0.116137 (  0.116160)
MiniCache                              0.125378   0.000317   0.125695 (  0.125698)
LruRedux                               0.063347   0.000985   0.064332 (  0.064338)
FastCache                              0.250153   0.005105   0.255258 (  0.255259)
MemoryStore                            1.690648   0.014256   1.704904 (  1.705235)
--------------------------------------------------------------- total: 3.826046sec

                                           user     system      total        real
OmniCache                              0.704022   0.008542   0.712564 (  0.712790)
OmniCache (non-threadsafe)             0.701127   0.008492   0.709619 (  0.709617)
OmniCache (identity, non-threadsafe)   0.122206   0.001102   0.123308 (  0.123327)
MiniCache                              0.132258   0.000939   0.133197 (  0.133229)
LruRedux                               0.064900   0.001265   0.066165 (  0.066165)
FastCache                              0.370078   0.006666   0.376744 (  0.376861)
MemoryStore                            2.063579   0.020023   2.083602 (  2.083810)
```

## Acknowledgments

OmniCache is inspired by many caching libraries that have come before it, including:

* mini_cache: https://github.com/derrickreimer/mini_cache
* fast_cache: https://github.com/swoop-inc/fast_cache
* lru_redux: https://github.com/SamSaffron/lru_redux
* activesupport: https://github.com/rails/rails/tree/main/activesupport
