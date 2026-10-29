require_relative 'test_helper'

class IdentityTest < CrackdealerTest
  def test_normalization_preserves_version_and_accents
    assert_equal 'constant', defined?(Crackdealer::Identity), 'identity implementation is not loaded yet'

    assert_equal 'björk', Crackdealer::Identity.normalize('  Björk  ')
    assert_equal 'café', Crackdealer::Identity.normalize("  Cafe\u0301  ")
    refute_equal Crackdealer::Identity.normalize('Song'), Crackdealer::Identity.normalize('Song (Live)')
  end

  def test_normalization_uses_nfkc_and_collapses_whitespace
    assert_equal 'constant', defined?(Crackdealer::Identity), 'identity implementation is not loaded yet'

    assert_equal 'foo & bar', Crackdealer::Identity.normalize("  Ｆoo  &\t Bar  ")
    assert_equal '', Crackdealer::Identity.normalize(nil)
  end

  def test_recording_key_normalizes_artist_title_and_version
    assert_equal 'constant', defined?(Crackdealer::Identity), 'identity implementation is not loaded yet'

    first_key = Crackdealer::Identity.recording_key(artist: ' Björk ', title: 'Song', version_label: ' Live ')
    equivalent_key = Crackdealer::Identity.recording_key(artist: 'björk', title: 'Song', version_label: 'Live')
    album_independent_key = Crackdealer::Identity.recording_key(artist: 'björk', title: 'Song', version_label: 'Live')
    studio_key = Crackdealer::Identity.recording_key(artist: 'björk', title: 'Song')

    assert_equal first_key, equivalent_key
    assert_equal first_key, album_independent_key
    refute_equal first_key, studio_key
    assert_match(/\A[0-9a-f]{64}\z/, first_key)
  end
end
