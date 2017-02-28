import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { fakeAudio } from 'frontend/tests/helpers/ember_helper';
import stashes from '../../utils/_stashes';
import capabilities from '../../utils/capabilities';
import speecher from '../../utils/speecher';
import persistence from '../../utils/persistence';
import Ember from 'ember';

describe('speecher', function() {
  beforeEach(function() {
    speecher.audio = {};
    speecher.scope = window;
  });

  afterEach(function() {
    speecher.scope = window;
  });

  describe("speak_text", function() {
    it("should not error unexpectedly on bad input", function() {
      var spoken = false;
      stub(window.speechSynthesis, 'speak', function() { spoken = true; });
      window.speechSynthesis.bacon = 'asdf';
      expect(function() { speecher.speak_text(null); }).not.toThrow();
      expect(spoken).toEqual(false);
      expect(function() { speecher.speak_text(1234); }).not.toThrow();
      waitsFor(function() { return spoken; });
      runs();
    });

    it("should trigger speech synthesis", function() {
      var spoken = null;
      stub(window.speechSynthesis, 'speak', function(u) { spoken = u.text; });
      expect(function() { speecher.speak_text("hippo"); }).not.toThrow();
      waitsFor(function() { return spoken; });
      runs(function() {
        expect(spoken).toEqual("hippo");
      });
    });

    it("should cancel any existing text utterances", function() {
      var utterance = null;
      var cancelled = false;
      stub(window.speechSynthesis, 'speak', function(u) { utterance = u; });
      stub(window.speechSynthesis, 'cancel', function() { cancelled = true; });
      stub(speecher.scope, 'SpeechSynthesisUtterance', function() { });

      speecher.set('voices', [{'default': true, lang: 'asdf'}]);
      speecher.speak_text("hippo");
      waitsFor(function() { return cancelled && utterance; });
      runs(function() {
        expect(cancelled).toEqual(true);
        expect(utterance.text).toEqual("hippo");
        expect(utterance.voice).toNotEqual(null);
        expect(utterance.lang).toEqual('asdf');
      });
    });
    it("should not set a voiceURI or voice or lang for force_default voice", function() {
      var cancelled = false;
      var utterance = null;
      stub(window.speechSynthesis, 'speak', function(u) { utterance = u; });
      stub(window.speechSynthesis, 'cancel', function() { cancelled = true; });
      speecher.speak_text("hippo", 'asdf', {voiceURI: 'force_default'});
      waitsFor(function() { return cancelled && utterance; });
      runs(function() {
        expect(cancelled).toEqual(true);
        expect(utterance.voice).toEqual(null);
        expect(utterance.lang).toEqual('');
        expect(utterance.text).toEqual("hippo");
      });
    });
    it("should speak using alternate voice settings if specified", function() {
      var cancelled = false;
      var utterance = null;
      speecher.alternate_volume = 0.5;
      speecher.alternate_pitch = 2.0;
      speecher.alternate_voiceURI = 'bacon';

      stub(window.speechSynthesis, 'speak', function(u) { utterance = u; });
      stub(window.speechSynthesis, 'cancel', function() { cancelled = true; });
      speecher.speak_text("hippo", 'asdf', {alternate_voice: true});
      waitsFor(function() { return cancelled && utterance; });
      runs(function() {
        expect(cancelled).toEqual(true);
        expect(utterance.voiceURI).toEqual('bacon');
        expect(utterance.volume).toEqual(0.5);
        expect(utterance.pitch).toEqual(2.0);
        expect(utterance.text).toEqual("hippo");
      });
    });
  });

  describe("default_rate", function() {
    it("should have reasonable default rates based on device", function() {
      var orig_s = capabilities.system;
      var orig_b = capabilities.browser;
      var orig_v = capabilities.system_version;

      capabilities.system = 'Android';
      expect(speecher.default_rate()).toEqual(1.0);
      capabilities.browser = 'Safari';
      expect(speecher.default_rate()).toEqual(1.0);
      capabilities.system_version = 6;
      expect(speecher.default_rate()).toEqual(1.0);
      capabilities.system = 'iOS';
      expect(speecher.default_rate()).toEqual(0.2);
      capabilities.system_version = 9.1;
      expect(speecher.default_rate()).toEqual(1.0);
      capabilities.system_version = 8.0;
      expect(speecher.default_rate()).toEqual(0.2);
      capabilities.browser = 'Web Browser';
      expect(speecher.default_rate()).toEqual(1.0);

      capabilities.system = orig_s;
      capabilities.browser = orig_b;
      capabilities.system_version = orig_v;
    });
  });

  describe("set_voice", function() {
    it("should not error if set_voice has not been called", function() {
      stub(window.speechSynthesis, 'speak', function() { });
      expect(function() { speecher.speak_text("hippo"); }).not.toThrow();
    });
    it("should set pitch and volume based on settings", function() {
      speecher.set_voice({volume: 0.5, pitch: 2.0});
      expect(speecher.volume).toEqual(0.5);
      expect(speecher.pitch).toEqual(2.0);
    });
    it("should set alternate pitch and volume based on settings", function() {
      speecher.set_voice({volume: 0.5, pitch: 2.0}, {volume: 0.2, pitch: 1.0});
      expect(speecher.volume).toEqual(0.5);
      expect(speecher.pitch).toEqual(2.0);
      expect(speecher.alternate_volume).toEqual(0.5);
      expect(speecher.alternate_pitch).toEqual(2.0);
    });
  });

  describe("speak_audio", function() {
    var audio = null;
    beforeEach(function() {
      audio = fakeAudio();
      speecher.speaking_from_collection = null;
      stub(speecher, 'find_or_create_element', function() {
        return [audio];
      });
    });
    it("should not error unexpectedly on bad input", function() {
      speecher.speak_audio(null);
      expect(speecher.audio.text).toEqual(audio);
      expect(audio.listenersAdded).toEqual(true);
      expect(audio.listenersRemoved).not.toEqual(true);
    });
    it("should trigger audio", function() {
      speecher.speak_audio("http://sound.com/boom.mp3");
      waitsFor(function() { return audio.playCalled; });
      runs(function() {
        expect(speecher.audio.text).toEqual(audio);
        expect(audio.pauseCalled).toEqual(true);
        expect(audio.playCalled).toEqual(true);
        expect(audio.listenersAdded).toEqual(true);
        expect(audio.listenersRemoved).not.toEqual(true);
      });
    });
    it("should not error unexpectedly when it can't find the sound element on the page", function() {
      stub(speecher, 'find_or_create_element', function() {
        return [];
      });
      expect(function() { speecher.speak_audio("http://sound.com/thank_you.mp3"); }).not.toThrow();
      expect(speecher.audio.text).toEqual(undefined);
    });
    it("should rewind sound in case re-playing the same sound again", function() {
      expect(audio.currentTime).not.toEqual(0);
      speecher.speak_audio("http://sound.com/boom.mp3");
      waitsFor(function() { return audio.playCalled; });
      runs(function() {
        expect(speecher.audio.text).toEqual(audio);
        expect(audio.pauseCalled).toEqual(true);
        expect(audio.playCalled).toEqual(true);
        expect(audio.currentTime).toEqual(0);
        expect(audio.listenersAdded).toEqual(true);
        expect(audio.listenersRemoved).not.toEqual(true);
      });
    });
    it("should cancel any existing text or foreground audio", function() {
      var audio2 = fakeAudio();
      var audio3 = fakeAudio();
      var cancelled = false;
      speecher.audio.text = audio2;
      speecher.audio.background = audio3;
      stub(window.speechSynthesis, 'cancel', function() { cancelled = true; });
      speecher.speak_audio("http://sound.com/laugh.mp3");
      expect(audio.listenersAdded).toEqual(true);
      expect(audio.listenersRemoved).not.toEqual(true);
      expect(audio2.pauseCalled).toEqual(true);
      expect(audio2.listenersRemoved).toEqual(true);
      expect(cancelled).toEqual(true);
      expect(audio3.pauseCalled).not.toEqual(true);
      expect(audio3.listenersRemoved).not.toEqual(true);
    });
  });

  describe("speak_background_audio", function() {
    var audio = null;
    beforeEach(function() {
      audio = fakeAudio();
      stub(speecher, 'find_or_create_element', function() {
        return [audio];
      });
    });
    it("should not error unexpectedly on bad input", function() {
      speecher.speak_background_audio(null);
      expect(speecher.audio.background).toEqual(audio);
      expect(audio.listenersAdded).toEqual(true);
      expect(audio.listenersRemoved).not.toEqual(true);
    });
    it("should trigger audio", function() {
      speecher.speak_background_audio("http://sound.com/boom.mp3");
      waitsFor(function() { return audio.playCalled; });
      runs(function() {
        expect(speecher.audio.background).toEqual(audio);
        expect(audio.pauseCalled).toEqual(true);
        expect(audio.playCalled).toEqual(true);
        expect(audio.listenersAdded).toEqual(true);
        expect(audio.listenersRemoved).not.toEqual(true);
      });
    });
    it("should cancel any existing background audio", function() {
      var audio2 = fakeAudio();
      speecher.audio.background = audio2;
      speecher.speak_background_audio("http://sound.com/laugh.mp3");
      expect(audio.listenersAdded).toEqual(true);
      expect(audio.listenersRemoved).not.toEqual(true);
      expect(audio2.pauseCalled).toEqual(true);
      expect(audio2.listenersRemoved).toEqual(true);
    });

    it("should not cancel text or foreground audio", function() {
      var audio2 = fakeAudio();
      var audio3 = fakeAudio();
      var cancelled = false;
      speecher.audio.text = audio2;
      speecher.audio.background = audio3;
      stub(window.speechSynthesis, 'cancel', function() { cancelled = true; });
      speecher.speak_background_audio("http://sound.com/laugh.mp3");
      expect(audio.listenersAdded).toEqual(true);
      expect(audio.listenersRemoved).not.toEqual(true);
      expect(audio2.pauseCalled).not.toEqual(true);
      expect(audio2.listenersRemoved).not.toEqual(true);
      expect(cancelled).toEqual(false);
      expect(audio3.pauseCalled).toEqual(true);
      expect(audio3.listenersRemoved).toEqual(true);
    });
  });

  describe("speak_collection", function() {
    it("should queue list of foreground audio or text events", function() {
      var called = false;
      stub(speecher, 'next_speak', function() { called = true; });
      speecher.speak_collection([{}, {}]);
      expect(speecher.speaks).not.toEqual(null);
      expect(speecher.speaks.length).toEqual(2);
      expect(called).toEqual(true);
    });
    it("should cancel any foreground audio or text, but not background", function() {
      var fg = fakeAudio();
      var bg = fakeAudio();
      speecher.audio.text = fg;
      speecher.audio.background = bg;
      var called = false;
      stub(speecher, 'next_speak', function() { called = true; });
      speecher.speak_collection([]);
      expect(speecher.audio.text).toEqual(null);
      expect(speecher.audio.background).not.toEqual(null);
      expect(fg.listenersRemoved).toEqual(true);
      expect(bg.listenersRemoved).not.toEqual(true);
    });

    it("should run through the full list of speaks", function() {
      var audio = fakeAudio();
      stub(speecher, 'find_or_create_element', function() {
        return [audio];
      });

      var words = [];
      var scope = {};
      window.polyfillSpeechSynthesis(scope);
      speecher.scope = scope;
      stub(scope.speechSynthesis, 'speak', function(u) {
        words.push(u.text);
        u.trigger('end');
      });
      speecher.speak_collection([{text: "halo"}, {sound: "http://sounds.com/cookie.mp3"}, {text: "snow"}]);
      waitsFor(function() { return audio.playCalled; });
      runs(function() {
        expect(words[0]).toEqual('halo');
        expect(speecher.audio.text).toEqual(audio);
        expect(audio.playCalled).toEqual(true);
      });
      waitsFor(function() { return words.length == 2; });
      runs(function() {
        expect(words).toEqual(['halo', 'snow']);
        expect(speecher.speaks.length).toEqual(0);
      });
    });
  });
  describe("load_beep", function() {
    it("should reject if no beep found", function() {
      var failed = false;
      stub(speecher, 'beep_url', null);
      speecher.load_beep().then(function() { }, function() {
        failed = true;
      });
      waitsFor(function() { return failed; });
      runs();
    });

    it("should perform a lookup if the beep element is found", function() {
      stub(speecher, 'beep_url', 'http://www.pic.com/pic.png');
      stub(persistence, 'find_url', function(url) {
        if(url === 'http://www.pic.com/pic.png') {
          return Ember.RSVP.resolve("abc");
        } else {
          return Ember.RSVP.reject();
        }
      });
      var resolved = false;
      speecher.load_beep().then(function() {
        resolved = true;
      });
      waitsFor(function() { return resolved; });
      runs(function() {
        expect(speecher.beep_url).toEqual('abc');
      });
    });

  });

  describe('text_direction', function() {
    it('should return the correct value', function() {
      speecher.voiceURI = null;
      speecher.set('voices', [{voiceURI: 'saar', lang: 'ar-SA'}, {voiceURI: 'enus', lang:'en-US'}]);
      expect(speecher.text_direction()).toEqual('ltr');
      speecher.voiceURI = 'saar';
      expect(speecher.text_direction()).toEqual('rtl');
      speecher.voiceURI = 'enus';
      expect(speecher.text_direction()).toEqual('ltr');
    });
  });
});
