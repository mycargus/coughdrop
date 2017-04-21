import Ember from 'ember';
import capabilities from './capabilities';
import persistence from './persistence';
import tts_voices from './tts_voices';
import app_state from './app_state';
import i18n from './i18n';

var speecher = Ember.Object.extend({
  beep_url: "https://opensymbols.s3.amazonaws.com/beep.mp3",
  chimes_url: "https://opensymbols.s3.amazonaws.com/chimes.mp3",
  voices: [],
  text_direction: function() {
    var voice = speecher.get('voices').find(function(v) { return v.voiceURI == speecher.voiceURI; });
    var locale = (voice && voice.lang) || navigator.language || 'en-US';
    return i18n.text_direction(locale);
  },
  refresh_voices: function() {
    var list = [];
    var voices = speecher.scope.speechSynthesis.getVoices();
    for(var idx = 0; idx < voices.length; idx++) {
      list.push((voices._list || voices)[idx]);
    }
    var _this = this;
    capabilities.tts.available_voices().then(function(voices) {
      var more_voices = [];
      voices.forEach(function(voice) {
        if(voice.active) {
          var ref_voice = tts_voices.find_voice(voice.voice_id);
          if(ref_voice) {
            voice.name = ref_voice.name;
            voice.locale = ref_voice.locale;
          }
          more_voices.push({
            lang: voice.locale,
            name: voice.name,
            voiceURI: "extra:" + voice.voice_id
          });
        }
      });
      _this.set('voices', more_voices.concat(list));
    }, function() { });
    if(list.length === 0) {
      list.push({
        name: "Default Voice",
        voiceURI: ""
      });
    }
    if(!this.get('voices') || this.get('voices').length === 0) {
      this.set('voices', list);
    }
    return list;
  },
  check_readiness: function() {
    if(!this.ready) {
      capabilities.tts.init();
    }
    this.ready = true;
    var ios = function() {
      // ios has a weird quirk where sometimes a list of voices shows
      // up, but sometimes it doesn't. this *might* help add consistency.
      // ref: http://stackoverflow.com/questions/28948562/web-speech-api-consistently-get-the-supported-speech-synthesis-voices-on-ios-sa
      var u = new window.SpeechSynthesisUtterance();
      u.text = "test";
      u.lang = "ja-JP";
      try {
        u.voice = {name: "ja-JP", voiceURI: "ja-JP", lang: "ja-JP", localService: true, default: true};
      } catch(e) { }
    };
    if(capabilities.system == 'iOS') {
//       Ember.run.later(ios, 1000);
    }
//     this.ready = !!(!speecher.scope.speechSynthesis.voiceList || speecher.scope.speechSynthesis.voiceList.length > 0);
  },
  set_voice: function(voice, alternate_voice) {
    this.pitch = voice.pitch;
    this.volume = voice.volume;
    this.rate = voice.rate;
    this.voiceURI = null;
    if(voice.voice_uri) {
      var voices = speecher.get('voices');
      var found_voice = voices.find(function(v) { return v.voiceURI == voice.voice_uri; });
      if(found_voice) {
        this.voiceURI = found_voice.voiceURI;
        this.voiceLang = found_voice.lang;
      } else if(voice.voice_uri == 'force_default') {
        this.voiceURI = 'force_default';
        this.voiceLang = navigator.language;
      } else if(!this.voiceURI && voices.length > 0) {
        this.voiceURI = voices[0].voiceURI;
        this.voiceLang = voices[0].lang;
      }
    }
    if(alternate_voice && alternate_voice.enabled && alternate_voice.voice_uri) {
      this.alternate_pitch = alternate_voice.pitch;
      this.alternate_volume = alternate_voice.volume;
      this.alternate_rate = alternate_voice.rate;
      this.alternate_voiceURI = null;
      var voices = speecher.get('voices');
      var found_voice = voices.find(function(v) { return v.voiceURI == alternate_voice.voice_uri; });
      if(found_voice) {
        this.alternate_voiceURI = found_voice.voiceURI;
        this.alternate_voiceLang = found_voice.lang;
      } else if(alternate_voice.voice_uri == 'force_default') {
        this.alternate_voiceURI = 'force_default';
        this.alternate_voiceLang = navigator.language;
      }
    }
  },
  default_rate: function() {
    var agent = navigator.userAgent.toLowerCase();
    var ios = capabilities.system == 'iOS';
    var too_fast_voice = (ios && capabilities.browser == 'Safari' && (!capabilities.system_version || capabilities.system_version < 9.0));
    if(too_fast_voice) {
      return 0.2;
    }
    return 1.0;
  },
  speak_id: 0,
  speak_text: function(text, collection_id, opts) {
    opts = opts || {};
    if(this.speaking_from_collection && !collection_id) {
      // lets the user start building their next sentence without interrupting the current one
      // TODO: this seems elegant right now, but it is actually a good idea?
      return;
    } else if(this.speaking && opts.interrupt === false) {
      return;
    }
    this.stop('text');
    if(!text) { return; }
    text = text.toString();
    text = text.replace(/…/, '...');
    // iOS TTS quirk
    if(text.replace(/\s+/g, '') == "I") { text = "eye"; }
    if(text.replace(/\s+/g, '') == "went") { text = "wend"; }
    var _this = this;
    var speak_id = this.speak_id++;
    this.last_speak_id = speak_id;
    var pieces = text.split(/\.\.\./);
    var next_piece = function() {
      var piece_text = pieces.shift();
      if(!piece_text) {
        if(_this.last_speak_id == speak_id) {
          _this.speak_end_handler(speak_id);
        }
      } else if(piece_text.length === 0 || piece_text.match(/^\s+$/)) {
        Ember.run.later(function() {
          if(_this.last_speak_id == speak_id) {
            next_piece();
          }
        }, 500);
      } else {
        _this.speak_raw_text(piece_text, collection_id, opts, function() {
          if(pieces.length > 0) {
            Ember.run.later(function() {
              if(_this.last_speak_id == speak_id) {
                next_piece();
              }
            }, 500);
          } else {
            if(_this.last_speak_id == speak_id) {
              _this.speak_end_handler(speak_id);
            }
          }
        });
      }
    };
    next_piece();
  },
  speak_raw_text: function(text, collection_id, opts, callback) {
    var _this = this;
    if(opts.alternate_voice) {
      opts.volume = this.alternate_volume || ((opts.volume || 1.0) * 0.75);
      opts.pitch = this.alternate_pitch;
      opts.rate = this.alternate_rate;
      opts.voiceURI = this.alternate_voiceURI;
      if(app_state.get('vocalization_locale')) {
        var set_locale = app_state.get('vocalization_locale').split(/[-_]/)[0].toLowerCase();
        var voice_locale = (_this.alternate_voiceLang || navigator.language).split(/[-_]/)[0].toLowerCase();
        if(set_locale != voice_locale) {
          var list = _this.get('voices').filter(function(v) { return v.lang && v.lang.split(/[-_]/)[0].toLowerCase() == set_locale; });
          opts.voiceURI = (list[1] && list[1].voiceURI) || (list[0] && list[0].voiceURI) || _this.alternate_voiceURI;
        }
      }
    }
    opts.rate = opts.rate || this.rate || this.default_rate();
    opts.volume = opts.volume || this.volume || 1.0;
    opts.pitch = opts.pitch || this.pitch || 1.0;
    if(!opts.voiceURI) {
      opts.voiceURI = this.voiceURI;
      if(app_state.get('vocalization_locale')) {
        var set_locale = app_state.get('vocalization_locale').split(/[-_]/)[0].toLowerCase();
        var voice_locale = (this.alternate_voiceLang || navigator.language).split(/[-_]/)[0].toLowerCase();
        if(set_locale != voice_locale) {
          var list = _this.get('voices').filter(function(v) { return v.lang && v.lang.split(/[-_]/)[0].toLowerCase() == set_locale; });
          opts.voiceURI = (list[1] && list[1].voiceURI) || (list[0] && list[0].voiceURI) || _this.voiceURI;
        }
      }
    }
    opts.voiceURI = opts.voiceURI || this.voiceURI;
    var _this = this;
    if(speecher.scope.speechSynthesis) {
      if(opts.interrupt !== false) {
        this.speaking = true;
        this.speaking_from_collection = collection_id;
      }
      var utterance = new speecher.scope.SpeechSynthesisUtterance();
      utterance.text = text;
      utterance.rate = opts.rate;
      utterance.volume = opts.volume;
      utterance.pitch = opts.pitch;
      utterance.voiceURI = opts.voiceURI;
      var voice = null;
      if(opts.voiceURI != 'force_default') {
        var voices = speecher.get('voices');
        voice = voices.find(function(v) { return v.voiceURI == opts.voiceURI; });
        voice = voice || voices.find(function(v) { return (v.name + " " + v.lang) == opts.voiceURI; });
        voice = voice || voices.find(function(v) { return v.lang == opts.voiceURI; });
        var locale = window.navigator.language.toLowerCase();
        var language = locale && locale.split(/-/)[0];
        voice = voice || voices.find(function(v) { return locale && v.lang && (v.lang.toLowerCase() == locale || v.lang.toLowerCase().replace(/-/, '_') == locale); });
        voice = voice || voices.find(function(v) { return language && v.lang && v.lang.toLowerCase().split(/[-_]/)[0] == language; });
        voice = voice || voices.find(function(v) { return v['default']; });
      }

      var speak_utterance = function() {
        if(opts.voiceURI != 'force_default') {
          utterance.voice = voice;
          if(voice) {
            utterance.lang = voice.lang;
          }
        }
        if(utterance.addEventListener) {
          utterance.addEventListener('end', function() {
            callback();
          });
        } else {
          utterance.onend = function() {
            callback();
          };
        }
        speecher.scope.speechSynthesis.speak(utterance);
      };

      if(voice && voice.voiceURI && voice.voiceURI.match(/^extra:/)) {
        var voice_id = voice.voiceURI.replace(/^extra:/, '');
        Ember.run.later(function() {
          capabilities.tts.speak_text(text, {
            voice_id: voice_id,
            pitch: utterance.pitch,
            volume: utterance.volume,
            rate: utterance.rate
          }).then(function() {
            // method won't be called until the text is done being spoken or was interrupted
            callback();
          }, function(err) {
            console.log("system speak error");
            console.log(err);
            // method call returns error, fallback to speechSynthesis
            speak_utterance();
          });
        });
      } else {
        var delay = (capabilities.installed_app && capabilities.system == 'Windows') ? 300 : 0;
        var _this = this;
        // TODO: this delay may no longer be needed when we update chromium/electron, but right
        // now it only speaks every other text string unless you wait an extra half-second or so.
        Ember.run.later(function() {
          speak_utterance.call(_this);
        }, delay);
      }
    } else {
      alert(text);
    }
  },
  next_speak: function() {
    if(this.speaks && this.speaks.length) {
      var speak = this.speaks.shift();
      if(speak.sound) {
        this.speak_audio(speak.sound, 'text', this.speaking_from_collection);
      } else if(speak.text) {
        var stashVolume = this.volume;
        if(speak.volume) { this.volume = speak.volume; }
        this.speak_text(speak.text, this.speaking_from_collection);
        this.volume = stashVolume;
      }
    } else {
      // console.log("no speaks left");
    }
  },
  speak_end_handler: function(speak_id) {
    if(speak_id == speecher.last_speak_id) {
      speecher.speaking_from_collection = false;
      speecher.speaking = false;
      speecher.next_speak();
    } else {
      // console.log('unexpected speak_id');
    }
  },
  speak_background_audio: function(url) {
    this.speak_audio(url, 'background');
  },
  load_beep: function() {
    var p1 = this.load_sound('beep_url');
    var p2 = this.load_sound('chimes_url');
    return Ember.RSVP.all_wait([p1, p2]);
  },
  load_sound: function(attr) {
    if(speecher[attr]) {
      if(speecher[attr].match(/^data:/)) { return Ember.RSVP.resolve(true); }
      else if(!speecher[attr].match(/^http/)) { return Ember.RSVP.resolve(true); }
      var find = persistence.find_url(speecher[attr], 'sound').then(function(data_uri) {
        if(data_uri) {
          speecher[attr] = data_uri;
          return true;
        } else {
          return persistence.store_url(speecher[attr], 'sound').then(function(data) {
            speecher[attr] = data.local_url || data.data_uri;
            return true;
          });
        }
      }, function() {
        return persistence.store_url(speecher[attr], 'sound').then(function(data) {
          speecher[attr] = data.local_url || data.data_uri;
          return true;
        });
      });
      return find.then(null, function(err) {
        console.log(err);
        return Ember.RSVP.reject(err);
      });
    } else {
      return Ember.RSVP.reject({error: "beep sound not saved"});
    }
  },
  play_audio: function(elem) {
    // the check for lastListener  is weird, but there was a lag where if you played
    // the same audio multiple times in a row then it would trigger an 'ended' event
    // on the newly-attached listener. This approach tacks on a new audio element
    // if that's likely to happen. The "throwaway" class and the setTimeouts in here
    // are all to help with that purpose.
    if(elem.lastListener || (capabilities.mobile && capabilities.browser == "Safari")) {
      var audio = document.createElement('audio');
      audio.style.display = "none";
      audio.src = elem.src;
      document.body.appendChild(audio);
      audio.load();
      audio.speak_id = elem.speak_id;
      audio.className = 'throwaway';
      elem = audio;
    }
    elem.pause();
    elem.currentTime = 0;
    var _this = this;
    var speak_id = elem.speak_id;
    if(elem.lastListener) {
      elem.removeEventListener('ended', elem.lastListener);
      elem.removeEventListener('pause', elem.lastListener);
      setTimeout(function() {
        elem.lastListener = null;
      }, 50);
    }
    var handler = function() {
      _this.speak_end_handler(speak_id);
    };
    elem.lastListener = handler;
    elem.addEventListener('ended', handler);
    elem.addEventListener('pause', handler);
    Ember.run.later(function() {
      elem.play();
    }, 10);
    return elem;
  },
  beep: function() {
    var beep = Ember.$("#beep")[0];
    if(!beep) {
      var audio = document.createElement('audio');
      audio.style.display = "none";
      audio.src = speecher.beep_url;
      audio.id = 'beep';
      document.body.appendChild(audio);
      audio.load();
      beep = audio;
    }
    if(beep) {
      this.play_audio(beep);
    } else {
      console.log("beep sound not found");
    }
  },
  speak_audio: function(url, type, collection_id, opts) {
    opts = opts || {};
    if(this.speaking_from_collection && !collection_id) {
      // lets the user start building their next sentence without interrupting the current one
      return;
    } else if(this.speaking && opts.interrupt === false) {
      return;
    }
    if(opts.interrupt !== false) {
      this.speaking = true;
    }
    this.audio = this.audio || {};
    type = type || 'text';
    this.stop(type);

    var $audio = this.find_or_create_element(url);
    if($audio.length) {
      var audio = $audio[0];
      if(type == 'text') {
        var speak_id = this.speak_id++;
        this.last_speak_id = speak_id;
        this.speaking = true;
        this.speaking_from_collection = collection_id;
        audio.speak_id = speak_id;
      }
      var playing_audio = this.play_audio(audio);
      this.audio[type] = playing_audio;
    } else {
      console.log("couldn't find sound to play");
    }
  },
  find_or_create_element: function(url) {
    var $res = Ember.$("audio[src='" + url + "']");
    if($res.length === 0) {
      $res = Ember.$("audio[rel='" + url + "']");
    }
    return $res;
  },
  speak_collection: function(list, collection_id, opts) {
    this.stop('text');
    this.speaks = list;
    if(opts && opts.override_volume) {
      list.forEach(function(s) { s.volume = opts.override_volume; });
    }
    if(list && list.length > 0) {
      this.speaking_from_collection = collection_id;
      this.next_speak();
    }
  },
  stop: function(type) {
    this.audio = this.audio || {};
    type = type || 'all';
    Ember.$("audio.throwaway").remove();
    if(type == 'text' || type == 'all') {
      this.speaking = false;
      this.speaking_from_collection = false;
      // this.speaks = [];
      if((speecher.last_text || "").match(/put/)) { debugger; }
      speecher.scope.speechSynthesis.cancel();
      capabilities.tts.stop_text();
      if(this.audio.text) {
        this.audio.text.pause();
        this.audio.text.removeEventListener('ended', this.audio.text.lastListener);
        this.audio.text.removeEventListener('pause', this.audio.text.lastListener);
        var audio = this.audio.text;
        setTimeout(function() {
          audio.lastListener = null;
        }, 50);
        this.audio.text = null;
      }
    }
    if(type == 'background' || type == 'all') {
      if(this.audio.background) {
        this.audio.background.pause();
        this.audio.background.removeEventListener('ended', this.audio.background.lastListener);
        this.audio.background.removeEventListener('pause', this.audio.background.lastListener);
        var audio = this.audio.background;
        setTimeout(function() {
          audio.lastListener = null;
        }, 50);
        this.audio.background = null;
      }
    }
  }
}).create({scope: (window.polyspeech || window)});
speecher.check_readiness();
window.speecher = speecher;

export default speecher;
