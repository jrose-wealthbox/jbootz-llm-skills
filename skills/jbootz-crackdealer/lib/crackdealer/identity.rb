require 'digest'
require 'json'

module Crackdealer
  module Identity
    def self.normalize(text)
      return '' if text.nil?

      text.to_s.unicode_normalize(:nfkc).downcase.strip.gsub(/\s+/, ' ')
    end

    def self.recording_key(artist:, title:, version_label: nil)
      normalized_identity = [normalize(artist), normalize(title), normalize(version_label)]
      Digest::SHA256.hexdigest(JSON.generate(normalized_identity))
    end
  end
end
