import Ember from 'ember';
import EmberObject from '@ember/object';
import { later as runLater, cancel as runCancel } from '@ember/runloop';
import {set as emberSet, get as emberGet} from '@ember/object';
import i18n from './i18n';
import stashes from './_stashes';
import speecher from './speecher';
import app_state from './app_state';
import persistence from './persistence';
import $ from 'jquery';

var utterance = EmberObject.extend({
  setup: function(controller) {
    this.controller = controller;
    this.set('rawButtonList', stashes.get('working_vocalization'));
    app_state.addObserver('currentUser', this, this.update_voice);
    app_state.addObserver('currentUser.preferences.device.voice', this, this.update_voice);
    app_state.addObserver('currentUser.preferences.device.voice.volume', this, this.update_voice);
    app_state.addObserver('currentUser.preferences.device.voice.pitch', this, this.update_voice);
    app_state.addObserver('currentUser.preferences.device.voice.voiceURI', this, this.update_voice);
    app_state.addObserver('currentUser.preferences.clear_on_vocalize', this, this.update_voice);
//     this.set('clear_on_vocalize', window.user_preferences.any_user.clear_on_vocalize);
//     speecher.set_voice(window.user_preferences.device.voice);
    if(stashes.get('ghost_utterance')) {
      this.set('list_vocalized', true);
    }
  },
  update_voice: function() {
    var user = app_state.get('currentUser');
    if(user && user.get) {
      if(user.get && user.get('preferences.device.voice')) {
        user.update_voice_uri();
        speecher.set_voice(user.get('preferences.device.voice'), user.get('preferences.device.alternate_voice'));
      }
      this.set('clear_on_vocalize', user.get('preferences.clear_on_vocalize'));
    }
  },
  set_button_list: function() {
    var buttonList = [];
    var rawList = this.get('rawButtonList');
    if(!rawList) { app_state.set('button_list', []); return; }
    var find_one = function(list, look) { return list.find(function(e) { return e == look; }); };
    for(var idx = 0; idx < rawList.length; idx++) {
      var button = rawList[idx];
      var last = rawList[idx - 1] || {};
      var last_computed = buttonList[buttonList.length - 1];
      var text = (button && (button.vocalization || button.label)) || '';
      if(text.match(/^\+/) && !last.sound) {
        last = {};
        if(idx === 0 || last_computed.in_progress) {
          last = buttonList.pop() || {};
        }
        // append to previous
        var altered = this.modify_button(last, button);
        buttonList.push(altered);
      } else if(text.match(/^\:/) && !last.sound) {
        last = buttonList.pop();
        if((text == ':complete' || text == ':predict') && !(last || {}).in_progress) {
          if(last) {
            buttonList.push(last);
          }
          last = {};
        }
        var wordAction = find_one(this.modifiers, text);
        if(wordAction) {
          var altered = this.modify_button(last || {}, button);
          buttonList.push(altered);
        } else if(last) {
          buttonList.push(last);
        }
      } else {
        buttonList.push(rawList[idx]);
      }
    }
    var visualButtonList = [];
    buttonList.forEach(function(button) {
      var visualButton = EmberObject.create(button);
      visualButtonList.push(visualButton);
      if(button.image && button.image.match(/^http/)) {
        persistence.find_url(button.image, 'image').then(function(data_uri) {
          visualButton.set('image', data_uri);
        }, function() { });
      }
      if(button.sound && button.sound.match(/^http/)) {
        persistence.find_url(button.sound, 'image').then(function(data_uri) {
          visualButton.set('sound', data_uri);
        }, function() { });
      }
    });
    var last_spoken_button = visualButtonList[visualButtonList.length - 1];
    if(last_spoken_button && (last_spoken_button.vocalization || last_spoken_button.label || "").match(/^\s*[\.\?\,\!]\s*$/)) {
      var prior = utterance.sentence(visualButtonList.slice(0, -1));
      var parts = prior.split(/[\.\?\!]/);
      var last_part = parts[parts.length - 1];
      var str = last_part + " " + (last_spoken_button.vocalization || last_spoken_button.label);
      last_spoken_button = {
        label: str
      };
    }

    app_state.set('button_list', visualButtonList);
    utterance.set('last_spoken_button', last_spoken_button);
    stashes.persist('working_vocalization', buttonList);
  }.observes('rawButtonList', 'rawButtonList.[]', 'rawButtonList.length', 'rawButtonList.@each.image'),
  modifiers: [':plural', ':singular', ':comparative', ':er', ':superlative', ':verb-negation',
    ':est', ':possessive', ':\'s', ':past', ':ed', ':present-participle', ':ing', ':space', ':complete', ':predict'],
  modify_button: function(original, addition) {
    // TODO: I'm thinking maybe +s notation shouldn't append to word buttons, only :modify notation
    // should do that. The problem is when you want to spell a word after picking a word-button,
    // how exactly do you go about that? Make them type a space first? I guess maybe...
    var altered = $.extend({}, original);

    altered.modified = true;
    altered.button_id = altered.button_id || addition.button_id;
    altered.sound = null;
    altered.board = altered.board || addition.board;
    altered.modifications = altered.modifications || [];
    altered.modifications.push(addition);

    var parts = (addition.vocalization || addition.label || '').split(/\s*&&\s*/);
    parts.forEach(function(text) {
      if(text && text.length > 0) {
        var prior_text = (altered.vocalization || altered.label || '');
        var prior_label = (altered.label || '');
    
        if(text.match(/^\+/) && (altered.in_progress || !prior_text)) {
          altered.vocalization = prior_text + text.substring(1);
          altered.label = prior_label + text.substring(1);
          altered.in_progress = true;
        } else if(text == ':space') {
          altered.in_progress = false;
        } else if(text == ':complete' || text == ':predict') {
    
          altered.vocalization = addition.completion;
          altered.label = addition.completion;
          if(addition.image) { altered.image = addition.image; }
          altered.in_progress = false;
        } else if(text == ':plural' || text == ':pluralize') {
          altered.vocalization = i18n.pluralize(prior_text);
          altered.label = i18n.pluralize(prior_label);
          altered.in_progress = false;
        } else if(text == ':singular' || text == ':singularize') {
          altered.vocalization = i18n.singularize(prior_text);
          altered.label = i18n.singularize(prior_label);
          altered.in_progress = false;
        } else if(text == ':comparative' || text == ':er') {
          altered.vocalization = i18n.comparative(prior_text);
          altered.label = i18n.comparative(prior_label);
          altered.in_progress = false;
        } else if(text == ':superlative' || text == ':est') {
          altered.vocalization = i18n.superlative(prior_text);
          altered.label = i18n.superlative(prior_label);
          altered.in_progress = false;
        } else if(text == ':verb-negation' || text == ':\'t' || text == ':n\t') {
          altered.vocalization = i18n.verb_negation(prior_text);
          altered.label = i18n.verb_negation(prior_label);
          altered.in_progress = false;
        } else if(text == ':possessive' || text == ':\'s') {
          altered.vocalization = i18n.possessive(prior_text);
          altered.label = i18n.possessive(prior_label);
          altered.in_progress = false;
        } else if(text == ':past' || text == ':ed') {
          altered.vocalization = i18n.tense(prior_text, {simple_past: true});
          altered.label = i18n.tense(prior_label, {simple_past: true});
          altered.in_progress = false;
        } else if(text == ':present-participle' || text == ':ing') {
          altered.vocalization = i18n.tense(prior_text, {present_participle: true});
          altered.label = i18n.tense(prior_label, {present_participle: true});
          altered.in_progress = false;
        }
    
      }
    });

    var filler = 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/pencil%20and%20paper%202.svg';
    altered.image = altered.image || filler;
    if(!altered.in_progress && altered.image == filler) {
      altered.image = 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/paper.svg';
    }
    return altered;
  },
  specialty_button: function(button) {
    var vocs = [];
    (button.vocalization || '').split(/\s*&&\s*/).forEach(function(mod) {
      if(mod && mod.length > 0) { vocs.push(mod); }
    });
    var specialty = null;
    vocs.forEach(function(voc) {
      if(voc == ":beep" || voc == ":home" || voc == ":back" || voc == ":clear" || voc == ":speak" || voc == ":backspace" || voc == ':hush') {
        if(voc == ':beep' || voc == ':speak') {
          button.has_sound = true;
        }
        specialty = button;
      } else if(voc.match(/^\+/) || voc.match(/^:/)) {
        button.specialty_with_modifiers = true;
        if(voc.match(/^\+/) || voc == ':space' || voc == ':complete') {
          button.default_speak = true;
        }
        specialty = button;
      } else {
        if(button.default_speak) {
          button.default_speak = button.default_speak + " " + voc;
        } else {
          button.default_speak = voc;
        }
        specialty = button;
      }
    });
    return specialty;
  },
  add_button: function(button, original_button) {
    // clear if the sentence box was already spoken and auto-clear is enabled
    if(this.get('clear_on_vocalize') && this.get('list_vocalized')) {
      this.clear({auto_cleared: true});
    }
    // append button attributes as needed
    var b = $.extend({}, button);
    if(original_button && original_button.load_image) {
      original_button.load_image().then(function() {
        emberSet(b, 'image', original_button.get('image.best_url'));
        emberSet(b, 'image_license', original_button.get('image.license'));
      });
      original_button.load_sound().then(function() {
        emberSet(b, 'sound', original_button.get('sound.best_url'));
        emberSet(b, 'sound_license', original_button.get('sound.license'));
      });
    }
    // add button to the raw button list
    var list = this.get('rawButtonList');
    list.pushObject(b);
    this.set('list_vocalized', false);
    // retrieve the correct result from the now-updated button list
    // should return whatever it is the vocalization is supposed to say
    return utterance.get('last_spoken_button');
  },
  speak_button: function(button) {
    if(button.sound) {
      var collection_id = null;
      if(button.blocking_speech) {
        collection_id = Math.round(Math.random() * 99999) + "-" + (new Date()).getTime();
      }
      speecher.speak_audio(button.sound, 'text', collection_id);
    } else {
      if(speecher.ready) {
        if(button.vocalization == ":beep") {
          speecher.beep();
        } else {
          var collection_id = null;
          if(button.blocking_speech) {
            collection_id = Math.round(Math.random() * 99999) + "-" + (new Date()).getTime();
          }
          var text = button.vocalization || button.label;
          speecher.speak_text(text, collection_id);
        }
      } else {
        this.silent_speak_button(button);
      }
    }
  },
  sentence: function(u) {
      return u.map(function(b) { return b.vocalization || b.label; }).join(" ");
  },
  silent_speak_button: function(button) {
    var selector = '#speak_mode';
    if(app_state.get('speak_mode')) {
      selector = '#button_list';
    }
    if(!$(selector).attr('data-popover')) {
      $(selector).attr('data-popover', true).popover({html: true});
    }
    runCancel(this._popoverHide);
    var str = button.vocalization || button.label;
    var text = "\"" + $('<div/>').text(str).html() + "\"";
    if(button.sound) {
      text = text + " <span class='glyphicon glyphicon-volume-up'></span>";
    }
    $(selector).attr('data-content', text).popover('show');

    this._popoverHide = runLater(this, function() {
      $(selector).popover('hide');
    }, 2000);
  },
  speak_text: function(text) {
    if(text == ':beep') {
      speecher.beep();
    } else {
      speecher.speak_text(text);
    }
  },
  alert: function(opts) {
    speecher.beep(opts);
  },
  clear: function(opts) {
    opts = opts || {}
    this.set('rawButtonList', []);
    if(!opts.skip_logging) {
      stashes.log({
        action: 'clear',
        button_triggered: opts.button_triggered
      });
    }
    if(!opts.auto_cleared) {
      speecher.stop('all');
    }
    this.set('list_vocalized', false);
  },
  backspace: function(opts) {
    opts = opts || {};
    var list = this.get('rawButtonList');
    // if the list is vocalized, backspace should take it back into building-mode
    if(!this.get('list_vocalized')) {
      list.popObject();
    } else {
      speecher.stop('all');
    }
    stashes.log({
      action: 'backspace',
      button_triggered: opts.button_triggered
    });
    this.set('list_vocalized', false);
  },
  set_and_say_buttons: function(buttons) {
    this.set('rawButtonList', buttons);
    this.controller.vocalize();
  },
  vocalize_list: function(volume, opts) {
    opts = opts || {};
    // TODO: this is ignoring volume right now :-(
    var list = app_state.get('button_list');
    var text = list.map(function(i) { return i.vocalization || i.label; }).join(' ');
    var items = [];
    for(var idx = 0; idx < list.length; idx++) {
      if(list[idx].sound) {
        items.push({sound: list[idx].sound});
      } else if(items.length && items[items.length - 1].text) {
        var item = items.pop();
        items.push({text: item.text + ' ' + (list[idx].vocalization || list[idx].label), volume: volume});
      } else {
        items.push({text: (list[idx].vocalization || list[idx].label), volume: volume});
      }
    }

    stashes.log({
      text: text,
      button_triggered: opts.button_triggered,
      buttons: stashes.get('working_vocalization')
    });
    speecher.speak_collection(items, Math.round(Math.random() * 99999) + '-' + (new Date()).getTime(), {override_volume: volume});
    this.set('list_vocalized', true);
  },
  set_ghost_utterance: function() {
    stashes.persist('ghost_utterance', !!(this.get('list_vocalized') && this.get('clear_on_vocalize')));
  }.observes('list_vocalized', 'clear_on_vocalize'),
  test_voice: function(voiceURI, rate, pitch, volume) {
    rate = parseFloat(rate);
    if(isNaN(rate)) { rate = 1.0; }
    pitch = parseFloat(pitch);
    if(isNaN(pitch)) { pitch = 1.0; }
    volume = parseFloat(volume);
    if(isNaN(volume)) { volume = 1.0; }

    speecher.speak_text(i18n.t('do_you_like_voice', "Do you like my voice?"), 'test-' + voiceURI, {
      volume: volume,
      pitch: pitch,
      rate: rate,
      voiceURI: voiceURI
    });
  }
}).create({scope: (window.polyspeech || window)});

export default utterance;
