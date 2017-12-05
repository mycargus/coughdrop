import Ember from 'ember';
import i18n from './i18n';
import stashes from './_stashes';
import speecher from './speecher';
import app_state from './app_state';
import persistence from './persistence';
import $ from 'jquery';

var utterance = Ember.Object.extend({
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
        if(text == ':complete' && !(last || {}).in_progress) {
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
      var visualButton = Ember.Object.create(button);
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

    app_state.set('button_list', visualButtonList);
    stashes.persist('working_vocalization', buttonList);
  }.observes('rawButtonList', 'rawButtonList.[]', 'rawButtonList.length', 'rawButtonList.@each.image'),
  modifiers: [':plural', ':singular', ':comparative', ':er', ':superlative',
    ':est', ':possessive', ':\'s', ':past', ':ed', ':present-participle', ':ing', ':space', ':complete'],
  modify_button: function(original, addition) {
    // TODO: I'm thinking maybe +s notation shouldn't append to word buttons, only :modify notation
    // should do that. The problem is when you want to spell a word after picking a word-button,
    // how exactly do you go about that? Make them type a space first? I guess maybe...
    var altered = Ember.$.extend({}, original);

    altered.modified = true;
    altered.button_id = altered.button_id || addition.button_id;
    altered.sound = null;
    altered.board = altered.board || addition.board;
    altered.modifications = altered.modifications || [];
    altered.modifications.push(addition);

    var text = addition.vocalization || addition.label;
    var prior_text = (altered.vocalization || altered.label || '');
    var prior_label = (altered.label || '');
    if(text.match(/^\+/) && (altered.in_progress || !prior_text)) {
      altered.vocalization = prior_text + text.substring(1);
      altered.label = prior_label + text.substring(1);
      altered.in_progress = true;
    } else if(text == ':space') {
      altered.in_progress = false;
    } else if(text == ':complete') {
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
    } else if(text == ':verb-negation' || text == ':\'t') {
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

    var filler = 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/pencil%20and%20paper%202.svg';
    altered.image = altered.image || filler;
    if(!altered.in_progress && altered.image == filler) {
      altered.image = 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/paper.svg';
    }
    return altered;
  },
  specialty_button: function(button) {
    if(button.vocalization == ":beep" || button.vocalization == ":home" || button.vocalization == ":back" || button.vocalization == ":clear" || button.vocalization == ":speak" || button.vocalization == ":backspace") {
      return button;
    }
    return null;
  },
  add_button: function(button, original_button) {
    if(this.get('clear_on_vocalize') && this.get('list_vocalized')) {
      this.clear(true);
    }
    var b = Ember.$.extend({}, button);
    if(original_button && original_button.load_image) {
      original_button.load_image().then(function() {
        Ember.set(b, 'image', original_button.get('image.best_url'));
        Ember.set(b, 'image_license', original_button.get('image.license'));
      });
      original_button.load_sound().then(function() {
        Ember.set(b, 'sound', original_button.get('sound.best_url'));
        Ember.set(b, 'sound_license', original_button.get('sound.license'));
      });
    }
    var list = this.get('rawButtonList');
    list.pushObject(b);
    this.set('list_vocalized', false);
    return app_state.get('button_list')[app_state.get('button_list').length - 1];
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
          speecher.speak_text(button.vocalization || button.label, collection_id);
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
    Ember.run.cancel(this._popoverHide);
    var text = "\"" + $('<div/>').text(button.vocalization || button.label).html() + "\"";
    if(button.sound) {
      text = text + " <span class='glyphicon glyphicon-volume-up'></span>";
    }
    $(selector).attr('data-content', text).popover('show');

    this._popoverHide = Ember.run.later(this, function() {
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
  alert: function() {
    speecher.beep();
  },
  clear: function(auto_cleared, skip_logging) {
    this.set('rawButtonList', []);
    if(!skip_logging) {
      stashes.log({
        action: 'clear'
      });
    }
    if(!auto_cleared) {
      speecher.stop('all');
    }
    this.set('list_vocalized', false);
  },
  backspace: function() {
    var list = this.get('rawButtonList');
    // if the list is vocalized, backspace should take it back into building-mode
    if(!this.get('list_vocalized')) {
      list.popObject();
    } else {
      speecher.stop('all');
    }
    stashes.log({
      action: 'backspace'
    });
    this.set('list_vocalized', false);
  },
  set_and_say_buttons: function(buttons) {
    this.set('rawButtonList', buttons);
    this.controller.vocalize();
  },
  vocalize_list: function(volume) {
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
    if(isNaN(rate)) { rate = speecher.default_rate(); }
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
