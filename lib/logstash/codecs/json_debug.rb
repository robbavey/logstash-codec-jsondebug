# encoding: utf-8
require "logstash/codecs/base"
require "logstash/util/charset"
require "logstash/json"
require "logstash/event"

# This codec may be used to decode (via inputs) and encode (via outputs)
# full Jsondebug messages. If the data being sent is a Jsondebug array at its root multiple events will be created (one per element).
#
# If you are streaming Jsondebug messages delimited
# by '\n' then see the `json_lines` codec.
#
# Encoding will result in a compact Jsondebug representation (no line terminators or indentation)
#
# If this codec recieves a payload from an input that is not valid Jsondebug, then
# it will fall back to plain text and add a tag `_jsonparsefailure`. Upon a Jsondebug
# failure, the payload will be stored in the `message` field.
class LogStash::Codecs::JsonDebug < LogStash::Codecs::Base
  config_name "jsondebug"

  # The character encoding used in this codec. Examples include "UTF-8" and
  # "CP1252".
  #
  # Jsondebug requires valid UTF-8 strings, but in some cases, software that
  # emits Jsondebug does so in another encoding (nxlog, for example). In
  # weird cases like this, you can set the `charset` setting to the
  # actual encoding of the text and Logstash will convert it for you.
  #
  # For nxlog users, you may to set this to "CP1252".
  config :charset, :validate => ::Encoding.name_list, :default => "UTF-8"

  config :pretty, :validate => :boolean, :default => false

  config :metadata, :validate => :boolean, :default => false

  def register
    @converter = LogStash::Util::Charset.new(@charset)
    @converter.logger = @logger
  end

  def decode(data, &block)
    parse(@converter.convert(data), &block)
  end

  def encode(event)
    if metadata
      @on_event.call(event, LogStash::Json.dump(event.to_hash_with_metadata, {:pretty => pretty}) + NL)
    else
      @on_event.call(event, LogStash::Json.dump(event.to_hash, {:pretty => pretty}) + NL)
    end
  end

  private

  def from_json_parse(json, &block)
    LogStash::Event.from_json(json).each { |event| yield event }
  rescue LogStash::Json::ParserError => e
    @logger.error("Jsondebug parse error, original data now in message field", :error => e, :data => json)
    yield LogStash::Event.new("message" => json, "tags" => ["_jsonparsefailure"])
  end

  def legacy_parse(json, &block)
    decoded = LogStash::Json.load(json)

    case decoded
    when Array
      decoded.each {|item| yield(LogStash::Event.new(item)) }
    when Hash
      yield LogStash::Event.new(decoded)
    else
      @logger.error("Jsondebug codec is expecting array or object/map", :data => json)
      yield LogStash::Event.new("message" => json, "tags" => ["_jsonparsefailure"])
    end
  rescue LogStash::Json::ParserError => e
    @logger.info("Jsondebug parse failure. Falling back to plain-text", :error => e, :data => json)
    yield LogStash::Event.new("message" => json, "tags" => ["_jsonparsefailure"])
  rescue StandardError => e
    # This should NEVER happen. But hubris has been the cause of many pipeline breaking things
    # If something bad should happen we just don't want to crash logstash here.
    @logger.warn(
      "An unexpected error occurred parsing Jsondebug data",
      :data => json,
      :message => e.message,
      :class => e.class.name,
      :backtrace => e.backtrace
    )
  end

  # keep compatibility with all v2.x distributions. only in 2.3 will the Event#from_json method be introduced
  # and we need to keep compatibility for all v2 releases.
  alias_method :parse, LogStash::Event.respond_to?(:from_json) ? :from_json_parse : :legacy_parse

end
