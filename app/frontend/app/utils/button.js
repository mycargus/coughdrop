import Ember from 'ember';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import { later as runLater } from '@ember/runloop';
import $ from 'jquery';
import RSVP from 'rsvp';
import CoughDrop from '../app';
import boundClasses from './bound_classes';
import app_state from './app_state';
import persistence from './persistence';
import i18n from './i18n';
import stashes from './_stashes';
import progress_tracker from './progress_tracker';
import { htmlSafe } from '@ember/string';

var clean_url = function(str) {
  str = str || "";
  return str.replace(/"/g, "%22");
};
var dom = document.createElement('div');
var clean_text = function(str) {
  dom.textContent = str;
  return dom.innerHTML;
};

var Button = EmberObject.extend({
  init: function() {
    this.updateAction();
    this.add_classes();
    this.set_video_url();
    this.findContentLocally();
    this.set('stashes', stashes);
  },
  buttonAction: 'talk',
  updateAction: function() {
    if(this.get('load_board')) {
      this.set('buttonAction', 'folder');
    } else if(this.get('integration') != null) {
      this.set('buttonAction', 'integration');
      if(this.get('integration.action_type') == 'webhook') {
        this.set('integrationAction', 'webhook');
      } else {
        this.set('integrationAction', 'render');
      }
    } else if(this.get('url') != null) {
      this.set('buttonAction', 'link');
    } else if(this.get('apps') != null) {
      this.set('buttonAction', 'app');
    } else {
      this.set('buttonAction', 'talk');
    }
  }.observes('load_board', 'url', 'apps', 'integration', 'video', 'book', 'link_disabled'),
  talkAction: function() {
    return this.get('buttonAction') == 'talk';
  }.property('buttonAction'),
  folderAction: function() {
    return this.get('buttonAction') == 'folder';
  }.property('buttonAction'),
  integrationAction: function() {
    return this.get('buttonAction') == 'integration' && this.get('integrationAction') == 'render';
  }.property('buttonAction', 'integrationAction'),
  integrationOrWebhookAction: function() {
    return this.get('buttonAction') == 'integration';
  }.property('buttonAction'),
  webhookAction: function() {
    return this.get('buttonAction') == 'integration' && this.get('integrationAction') == 'webhook';
  }.property('buttonAction', 'integrationAction'),
  action_styling: function() {
    return Button.action_styling(this.get('buttonAction'), this);
  }.property('buttonAction', 'home_lock', 'book.popup', 'video.popup', 'action_status', 'action_status.pending', 'action_status.errored', 'action_status.completed', 'integration.action_type'),
  action_class: function() {
    return htmlSafe(this.get('action_styling.action_class'));
  }.property('action_styling'),
  action_image: function() {
    return this.get('action_styling.action_image');
  }.property('action_styling'),
  action_alt: function() {
    return this.get('action_styling.action_alt');
  }.property('action_styling'),
  resource_from_url: function() {
    var url = this.get('url');
    var resource = Button.resource_from_url(url);
    if(resource && resource.type == 'video' && resource.video_type == 'youtube') {
      if(this.get('video.id') != resource.id) {
        this.set('video', {
          type: 'youtube',
          id: resource.id,
          popup: true,
          start: "",
          end: ""
        });
      }
    } else {
      if(resource && resource.type == 'book' && resource.book_type == 'tarheel') {
        if(this.get('book.id') != resource.id) {
          this.set('book', {
            type: 'tarheel',
            id: resource.id,
            popup: true,
            speech: false,
            utterance: true,
            background: 'white',
            base_url: url,
            position: 'text_below',
            links: 'large'
          });
        }
      } else {
        this.set('book', null);
      }
      this.set('video', null);
    }
  }.observes('url'),
  set_book_url: function() {
    if(this.get('book.type') == 'tarheel' && this.get('book.popup') && this.get('book.base_url')) {
      var book = this.get('book');
      var new_url = this.get('book.base_url').split(/\?/)[0] + "?";
      if(book.speech) {
        new_url = new_url + "voice=browser";
      } else {
        new_url = new_url + "voice=silent";
      }
      if(book.background == 'black') {
        new_url = new_url + "&pageColor=000&textColor=fff";
      } else {
        new_url = new_url + "&pageColor=fff&textColor=000";
      }
      if(book.links == 'small') {
        new_url = new_url + "&biglinks=0";
      } else {
        new_url = new_url + "&biglinks=2";
      }
      this.set('book.url', new_url);
    }
  }.observes('book.popup', 'book.type', 'book.base_url', 'book.id', 'book.speech', 'book.background', 'book.links'),
  set_video_url: function() {
    if(this.get('video.type') == 'youtube' && this.get('video.popup') && this.get('video.id')) {
      var video = this.get('video');
      var new_url = "https://www.youtube.com/embed/" + video.id + "?rel=0&showinfo=0&enablejsapi=1&origin=" + encodeURIComponent(location.origin);
      if(video.start) {
        new_url = new_url + "&start=" + video.start;
      }
      if(video.end) {
        new_url = new_url + "&end=" + video.end;
      }
      this.set('video.url', new_url + "&autoplay=1&controls=0");
      this.set('video.thumbnail_url', "https://img.youtube.com/vi/" + this.get('video.id') + "/hqdefault.jpg");
      this.set('video.thumbnail_content_type', 'image/jpeg');
      this.set('video.test_url', new_url + "&autoplay=0");
    }
  }.observes('video.popup', 'video.type', 'video.id', 'video.start', 'video.end'),
  videoAction: function() {
    return this.get('buttonAction') == 'link' && this.get('video.popup');
  }.property('buttonAction', 'video.popup'),
  linkAction: function() {
    return this.get('buttonAction') == 'link';
  }.property('buttonAction'),
  appAction: function() {
    return this.get('buttonAction') == 'app';
  }.property('buttonAction'),
  empty_or_hidden: function() {
    return !!(this.get('empty') || (this.get('hidden') && !this.get('stashes.all_buttons_enabled')));
  }.property('empty', 'hidden', 'stashes.all_buttons_enabled'),
  add_classes: function() {
    boundClasses.add_rule(this);
    boundClasses.add_classes(this);
  }.observes('background_color', 'border_color', 'empty', 'hidden', 'link_disabled'),
  link: function() {
    if(this.get('load_board.key')) {
      return "/" + this.get('load_board.key');
    }
    return "";
  }.property('load_board.key'),
  icon: function() {
    if(this.get('load_board.key')) {
      return "/" + this.get('load_board.key') + "/icon";
    }
    return "";
  }.property('load_board.key'),
  fixed_url: function() {
    var url = this.get('url');
    if(url && !url.match(/^http/) && !url.match(/^book:/)) {
      url = "http://" + url;
    }
    return url;
  }.property('url'),
  fixed_app_url: function() {
    var url = this.get('apps.web.launch_url');
    if(url && !url.match(/^http/)) {
      url = "http://" + url;
    }
    return url;
  }.property('apps.web.launch_url'),
  levels_list: function() {
    var levels = [];
    var mods = this.get('level_modifications') || {};
    for(var idx in mods) {
      if(parseInt(idx, 10) > 0) {
        levels.push(parseInt(idx, 10));
      }
    }
    levels = levels.sort();
    if(levels.length > 0) {
      return "L" + levels.join(' ');
    } else {
      return null;
    }
  }.property('level_modifications'),
  apply_level: function(level) {
    var mods = this.get('level_modifications') || {};
    var _this = this;
    var keys = ['pre'];
    for(var idx = 0; idx <= level; idx++) { keys.push(idx); }
    keys.push('override');
    keys.forEach(function(key) {
      if(mods[key]) {
        for(var attr in mods[key]) {
          _this.set(attr, mods[key][attr]);
        }
      }
    });
  },
  fast_html: function() {
    var res = "";
    if(this.get('board.display_level') && this.get('level_modifications')) {
      if(this.get('board.display_level') == this.get('board.default_level')) {
      } else {
        var mods = this.get('level_modifications');
        var level = this.get('board.display_level');
        if(mods.override) {
          for(var key in mods.override) {
            this.set(key, mods.override[key]);
          }
        }
        if(mods.pre) {
          for(var key in mods.pre) {
            if(!mods.override || mods.override[key] === null || mods.override[key] === undefined) {
              this.set(key, mods.pre[key]);
            }
          }
        }
        for(var idx = 1; idx <= level; idx++) {
          if(mods[idx]) {
            for(var key in mods[idx]) {
              if(!mods.override || mods.override[key] === null || mods.override[key] === undefined) {
                this.set(key, mods[idx][key]);
              }
            }
          }
        }
      }
    }
    res = res + "<div style='" + this.get('computed_style') + "' class='" + this.get('computed_class') + "' data-id='" + this.get('id') + "' tabindex='0'>";
    if(this.get('pending')) {
      res = res + "<div class='pending'><img src='" + Ember.templateHelpers.path('images/spinner.gif') + "' /></div>";
    }
    res = res + "<div class='" + this.get('action_class') + "'>";
    res = res + "<span class='action'>";
    res = res + "<img src='" + this.get('action_image') + "' alt='" + this.get('action_alt') + "' />";
    res = res + "</span>";
    res = res + "</div>";

    res = res + "<span style='" + this.get('image_holder_style') + "'>";
    if(!app_state.get('currentUser.hide_symbols') && this.get('local_image_url')) {
      res = res + "<img src=\"" + clean_url(this.get('local_image_url')) + "\" onerror='button_broken_image(this);' style='" + this.get('image_style') + "' class='symbol' />";
    }
    res = res + "</span>";
    if(this.get('sound')) {
      res = res + "<audio style='display: none;' preload='auto' src=\"" + clean_url(this.get('local_sound_url')) + "\" rel=\"" + clean_url(this.get('sound.url')) + "\"></audio>";
    }
    res = res + "<div class='" + app_state.get('button_symbol_class') + "'>";
    res = res + "<span class='" + (this.get('hide_label') ? "button-label hide-label" : "button-label") + "'>" + clean_text(this.get('label')) + "</span>";
    res = res + "</div>";

    res = res + "</div>";
    return htmlSafe(res);
  }.property('refresh_token', 'positioning', 'computed_style', 'computed_class', 'label', 'action_class', 'action_image', 'action_alt', 'image_holder_style', 'local_image_url', 'image_style', 'local_sound_url', 'sound.url', 'hide_label', 'level_modifications', 'board.display_level'),
  image_holder_style: function() {
    var pos = this.get('positioning');
    return htmlSafe(Button.image_holder_style(pos));
  }.property('positioning', 'positioning.image_height', 'positioning.image_top_margin', 'positioning.image_square'),
  image_style: function() {
    var pos = this.get('positioning');
    return htmlSafe(Button.image_style(pos));
  }.property('positioning', 'positioning.image_height', 'positioning.image_square'),
  computed_style: function() {
    var pos = this.get('positioning');
    if(!pos) { return htmlSafe(""); }
    return Button.computed_style(pos);
  }.property('positioning', 'positioning.height', 'positioning.width', 'positioning.left', 'positioning.top'),
  computed_class: function() {
    var res = this.get('display_class') + " ";
    if(this.get('board.text_size')) {
      res = res + this.get('board.text_size') + " ";
    }
    if(this.get('for_swap')) {
      res = res + "swapping ";
    }
    return res;
  }.property('display_class', 'board.text_size', 'for_swap'),
  pending: function() {
    return this.get('pending_image') || this.get('pending_sound');
  }.property('pending_image', 'pending_sound'),
  everything_local: function() {
    if(this.image_id && this.image_url && persistence.url_cache && persistence.url_cache[this.image_url] && (!persistence.url_uncache || !persistence.url_uncache[this.image_url])) {
    } else if(this.image_id && !this.get('image')) {
      var rec = CoughDrop.store.peekRecord('image', this.image_id);
      if(!rec || !rec.get('isLoaded')) { /* console.log("missing image for", this.get('label')); */ return false; }
    }
    if(this.sound_id && this.sound_url && persistence.url_cache && persistence.url_cache[this.sound_url] && (!persistence.url_uncache || !persistence.url_uncache[this.sound_url])) {
    } else if(this.sound_id && !this.get('sound')) {
      var rec = CoughDrop.store.peekRecord('sound', this.sound_id);
      if(!rec || !rec.get('isLoaded')) { /* console.log("missing sound for", this.get('label')); */ return false; }
    }
    return true;
  },
  load_image: function() {
    var _this = this;
    if(!_this.image_id) { return RSVP.resolve(); }
    var image = CoughDrop.store.peekRecord('image', _this.image_id);
    if(image && (!image.get('isLoaded') || !image.get('best_url'))) { image = null; }
    _this.set('image', image);
    if(!image) {
      if(_this.get('no_lookups')) {
        return RSVP.reject('no image lookups');
      } else {
        // TODO: if in Speak Mode, this shouldn't hold up the rendering
        // process, so if it has to make a remote call then consider
        // killing it or coming back to it somehow. Same applies for Sound records.
        return CoughDrop.store.findRecord('image', _this.image_id).then(function(image) {
          // There was a runLater of 100ms here, I have no idea why but
          // it seemed like a bad idea so I removed it.
          _this.set('image', image);
          return image.checkForDataURL().then(function() {
            _this.set('local_image_url', image.get('best_url'));
            return RSVP.resolve(image);
          }, function() {
            _this.set('local_image_url', image.get('best_url'));
            return RSVP.resolve(image);
          });
        });
      }
    } else {
      _this.set('local_image_url', image.get('best_url'));
      return image.checkForDataURL().then(function() {
        _this.set('local_image_url', image.get('best_url'));
      }, function() { return RSVP.resolve(image); });
    }
  },
  update_local_image_url: function() {
    if(this.get('image.best_url')) {
      this.set('local_image_url', this.get('image.best_url'));
    }
  }.observes('image.best_url'),
  load_sound: function() {
    var _this = this;
    if(!_this.sound_id) { return RSVP.resolve(); }
    var sound = CoughDrop.store.peekRecord('sound', _this.sound_id);
    if(sound && (!sound.get('isLoaded') || !sound.get('best_url'))) { sound = null; }
    _this.set('sound', sound);
    if(!sound) {
      if(_this.get('no_lookups')) {
        return RSVP.reject('no sound lookups');
      } else {
        return CoughDrop.store.findRecord('sound', _this.sound_id).then(function(sound) {
          _this.set('sound', sound);
          return sound.checkForDataURL().then(function() {
            _this.set('local_sound_url', sound.get('best_url'));
            return RSVP.resolve(sound);
          }, function() {
            _this.set('local_sound_url', sound.get('best_url'));
            return RSVP.resolve(sound);
          });
        });
      }
    } else {
      _this.set('local_sound_url', sound.get('best_url'));
      return sound.checkForDataURL().then(function() {
        _this.set('local_sound_url', sound.get('best_url'));
      }, function() { return RSVP.resolve(sound); });
    }
  },
  update_local_sound_url: function() {
    if(this.get('sound.best_url')) {
      this.set('local_sound_url', this.get('sound.best_url'));
    }
  }.observes('image.best_url'),
  update_translations: function() {
    var label_locale = app_state.get('label_locale') || this.get('board.translations.current_label') || this.get('board.locale') || 'en';
    var vocalization_locale = app_state.get('vocalization_locale') || this.get('board.translations.current_vocalization') || this.get('board.locale') || 'en';
    var _this = this;
    var res = _this.get('translations') || [];
    var hash = _this.get('translations_hash') || {};
    var idx = 0;
    for(var code in hash) {
      var label = hash[code].label;
      if(label_locale == code) { label = _this.get('label'); }
      var vocalization = hash[code].vocalization;
      if(vocalization_locale == code) { vocalization = _this.get('vocalization'); }
      if(res[idx]) {
        emberSet(res[idx], 'label', label);
        emberSet(res[idx], 'vocalization', vocalization);
      } else {
        res.push({
          code: code,
          locale: code,
          label: label,
          vocalization: vocalization
        });
      }
      idx++;
    }
    this.set('translations', res);
  }.observes('translations_hash', 'label', 'vocalization'),
  update_settings_from_translations: function() {
    var label_locale = app_state.get('label_locale') || this.get('board.translations.current_label') || this.get('board.locale') || 'en';
    var vocalization_locale = app_state.get('vocalization_locale') || this.get('board.translations.current_vocalization') || this.get('board.locale') || 'en';
    var _this = this;
    (this.get('translations') || []).forEach(function(locale) {
      if(locale.code == label_locale && locale.label) {
        _this.set('label', locale.label);
      }
      if(locale.code == vocalization_locale && locale.vocalization) {
        _this.set('vocalization', locale.vocalization);
      }
    });
  }.observes('translations.@each.label', 'translations.@each.vocalization'),
  findContentLocally: function() {
    var _this = this;
    if((!this.image_id || this.get('local_image_url')) && (!this.sound_id || this.get('local_sound_url'))) {
      _this.set('content_status', 'ready');
      return RSVP.resolve(true);
    }
    this.set('content_status', 'pending');
    return new RSVP.Promise(function(resolve, reject) {
      var promises = [];
      if(_this.image_id && _this.image_url && persistence.url_cache && persistence.url_cache[_this.image_url] && (!persistence.url_uncache || !persistence.url_uncache[_this.image_url])) {
        _this.set('local_image_url', persistence.url_cache[_this.image_url]);
        _this.set('original_image_url', _this.image_url);
        promises.push(RSVP.resolve());
      } else if(_this.image_id) {
        promises.push(_this.load_image());
      }
      if(_this.sound_id && _this.sound_url && persistence.url_cache && persistence.url_cache[_this.sound_url] && (!persistence.url_uncache || !persistence.url_uncache[_this.sound_url])) {
        _this.set('local_sound_url', persistence.url_cache[_this.sound_url]);
        _this.set('original_sound_url', _this.sound_url);
        promises.push(RSVP.resolve());
      } else if(_this.sound_id) {
        promises.push(_this.load_sound());
      }

      RSVP.all(promises).then(function() {
        _this.set('content_status', 'ready');
        resolve(true);
      }, function(err) {
        if(_this.get('no_lookups')) {
          _this.set('content_status', 'missing');
        } else {
          _this.set('content_status', 'errored');
        }
        resolve(false);
        return RSVP.resolve();
      });

      promises.forEach(function(p) { p.then(null, function() { }); });
    });
  }.observes('image_id', 'sound_id'),
  check_for_parts_of_speech: function() {
    if(app_state.get('edit_mode') && !this.get('empty') && this.get('label')) {
      var text = this.get('vocalization') || this.get('label');
      var _this = this;
      persistence.ajax('/api/v1/search/parts_of_speech', {type: 'GET', data: {q: text}}).then(function(res) {
        if(!_this.get('background_color') && !_this.get('border_color') && res && res.types) {
          var found = false;
          _this.set('parts_of_speech_matching_word', res.word);
          res.types.forEach(function(type) {
            if(!found) {
              CoughDrop.keyed_colors.forEach(function(color) {
                if(!found && color.types && color.types.indexOf(type) >= 0) {
                  _this.set('background_color', color.fill);
                  _this.set('border_color', color.border);
                  _this.set('part_of_speech', type);
                  _this.set('suggested_part_of_speech', type);
                  boundClasses.add_rule(_this);
                  boundClasses.add_classes(_this);
                  found = true;
                }
              });
            }
          });
        }
      }, function() { });
    }
  },
  raw: function() {
    var attrs = [];
    var ret = {};
    for(var key in this) {
      if (!this.hasOwnProperty(key)) { continue; }

      // Prevents browsers that don't respect non-enumerability from
      // copying internal Ember properties
      if (key.substring(0,2) === '__') { continue; }

      if (this.constructor.prototype[key]) { continue; }

      if (Button.attributes.includes(key)) {
        ret[key] = this.get(key);
      }
    }
    return ret;
  }
});
Button.attributes = ['label', 'background_color', 'border_color', 'image_id', 'sound_id', 'load_board',
            'hide_label', 'completion', 'hidden', 'link_disabled', 'vocalization', 'url', 'apps',
            'integration', 'video', 'book', 'part_of_speech', 'external_id', 'add_to_vocalization',
            'home_lock', 'blocking_speech', 'level_modifications'];

Button.style = function(style) {
  var res = {};

  style = style || "";
  if(style.match(/caps$/)) {
    res.upper = true;
  } else if(style.match(/small$/)) {
    res.lower = true;
  }
  if(style.match(/^comic_sans/)) {
    res.font_class = "comic_sans";
  } else if(style.match(/open_dyslexic/)) {
    res.font_class = "open_dyslexic";
  } else if(style.match(/architects_daughter/)) {
    res.font_class = "architects_daughter";
  }

  return res;
};

Button.computed_style = function(pos) {
    var str = "";
    if(pos && pos.top !== undefined && pos.left !== undefined) {
      str = str + "position: absolute;";
      str = str + "left: " + pos.left + "px;";
      str = str + "top: " + pos.top + "px;";
    }
    if(pos.width) {
      str = str + "width: " + Math.max(pos.width, 20) + "px;";
    }
    if(pos.height) {
      str = str + "height: " + Math.max(pos.height, 20) + "px;";
    }
    return htmlSafe(str);
};
Button.action_styling = function(action, button) {
  if(!action) {
    if(button.load_board) {
      action = 'folder';
    } else if(button.url != null) {
      action = 'link';
    } else if(button.apps != null) {
      action = 'app';
    } else if(button.integration != null) {
      if(button.integration.action_type == 'webhook') {
        action = 'webhook';
      } else {
        action = 'integration';
      }
    } else {
      action = 'talk';
    }
  } else if(action == 'integration' && button.integration && button.integration.action_type == 'webhook') {
    action = 'webhook'
  }
  var res = {};
  res.action_class = 'action_container ';
  if(action) { res.action_class = res.action_class + action + " "; }
  if(button.home_lock) { res.action_class = res.action_class + "home "; }

  var path = Ember.templateHelpers.path;
  if(action == 'folder') {
    if(button.home_lock) {
      res.action_image = path('images/folder_home.png');
    } else {
      res.action_image = path('images/folder.png');
    }
  } else if(action == 'integration' || action == 'webhook') {
    var state = button.action_status || {};
    if(button.integration && button.integration.action_type == 'render') {
      res.action_image = path('images/folder_integration.png');
    } else if(state.pending) {
      res.action_image = path('images/clock.png');
      res.action_class = res.action_class + "pending ";
    } else if(state.errored) {
      res.action_image = path('images/error.png');
      res.action_class = res.action_class + "errored ";
    } else if(state.completed) {
      res.action_image = path('images/check.png');
      res.action_class = res.action_class + "succeeded ";
    } else {
      res.action_image = path('images/action.png');
      res.action_class = res.action_class + "ready ";
    }
  } else if(action == 'talk') {
    res.action_image = path('images/talk.png');
  } else if(action == 'link') {
    if(button.video && button.video.popup) {
      res.action_image = path('images/video.svg');
    } else if(button.book && button.book.popup) {
      res.action_image = path('images/book.svg');
    } else {
      res.action_image = path('images/link.png');
    }
  } else if(action == 'app') {
    res.action_image = path('images/app.png');
  } else {
    res.action_image = path('images/unknown_action.png');
  }

  if(action == 'folder') {
    res.action_alt = i18n.t('folder', "folder");
  } else if(action == 'talk') {
    res.action_alt = i18n.t('talk', "talk");
  } else if(action == 'link') {
    if(button.video && button.video.popup) {
      res.action_alt = i18n.t('video', "video");
    } else if(button.book && button.book.popup) {
      res.action_alt = i18n.t('book', "book");
    } else {
      res.action_alt = i18n.t('link', "link");
    }
  } else if(action == 'app') {
    res.action_alt = i18n.t('app', "app");
  } else if(action == 'integration') {
    res.action_alt = i18n.t('integration', "integration");
  } else {
    res.action_alt = i18n.t('unknown_action', "unknown action");
  }

  return res;
};
Button.image_holder_style = function(pos) {
  if(!pos || !pos.image_height) { return ""; }
  return "margin-top: " + pos.image_top_margin + "px; vertical-align: top; display: inline-block; width: " + pos.image_square + "px; height: " + pos.image_height + "px; line-height: " + pos.image_height + "px;";
};
Button.image_style = function(pos) {
  if(!pos || !pos.image_height) { return ""; }
  return "width: 100%; vertical-align: middle; max-height: " + pos.image_square + "px;";
};
Button.clean_url = function(str) { return clean_url(str); };

Button.button_styling = function(button, board, pos) {
  var res = {};
  res.button_class = emberGet(button, 'display_class');
  if(board.get('text_size')) {
    res.button_class = res.button_class + " " + board.get('text_size') + " ";
  }
  // TODO: sanitize all these for safety?
  res.button_style = Button.computed_style(pos);
  var action = Button.action_styling(null, button);
  res.action_class = action.action_class; //"action_container talk"; // TODO
  res.action_image = action.action_image; //Ember.templateHelpers.path('images/folder.png'); // TODO
  res.action_alt = action.action_alt; //"alt"; // TODO
  res.image_holder_style = Button.image_holder_style(pos);
  res.image_style = Button.image_style(pos);
  res.label = clean_text(button.label); // TODO: clean

  return res;
};

Button.broken_image = function(image) {
  var fallback = Ember.templateHelpers.path('images/square.svg');
  if(image.src && image.src != fallback && !image.src.match(/^data/)) {
    console.log("bad image url: " + image.src);
    image.setAttribute('rel', image.src);
    if(image.getAttribute('data-fallback')) {
      fallback = image.getAttribute('data-fallback');
    } else {
      image.setAttribute('onerror', '');
    }
    var bad_src = image.src;
    image.src = fallback;
    persistence.find_url(fallback).then(function(data_uri) {
      if(image.src == fallback) {
        image.src = data_uri;
      }
    }, function() { });
    // try to recover from files disappearing from local storage
    var store_key = function(key) {
      persistence.url_cache[key] = false;
      persistence.store_url(key, 'image', false, true).then(function(data) {
        image.src = data.local_url || data.data_uri;
      }, function() { });
    };
    if(bad_src.match(/^file/)) {
      for(var key in persistence.url_cache) {
        if(bad_src == persistence.url_cache[key] && persistence.get('online')) {
          image.src = key;
          store_key(key);
        }
      }
    } else {
      persistence.find_url(bad_src).then(function(data_uri) {
        image.src = data_uri;
      }, function() { });
    }
  }
};


var youtube_regex = (/(?:https?:\/\/)?(?:www\.)?youtu(?:be\.com\/watch\?(?:.*?&(?:amp;)?)?v=|\.be\/)([\w \-]+)(?:&(?:amp;)?[\w\?=]*)?/);
var tarheel_reader_regex = (/(?:https?:\/\/)?(?:www\.)?tarheelreader\.org\/\d+\/\d+\/\d+\/([\w-]+)\/?/);
var book_regex = (/^book:(https?:\/\/.+)$/);
Button.resource_from_url = function(url) {
  var youtube_match = url && url.match(youtube_regex);
  var tarheel_match = url && url.match(tarheel_reader_regex);
  var book_match = url && url.match(book_regex);
  var youtube_id = youtube_match && youtube_match[1];
  var tarheel_id = tarheel_match && tarheel_match[1];
  var book_id = book_match && book_match[1];
  if(book_id && book_id.match(/www\.dropbox\.com/) && book_id.match(/\?dl=0$/)) {
    book_id = book_id.replace(/\?dl=0$/, '?dl=1');
  }
  if(youtube_id) {
    return {
      type: 'video',
      video_type: 'youtube',
      id: youtube_id
    };
  } else {
    var book_or_tarheel_id = tarheel_id || book_id;
    if(book_or_tarheel_id) {
      return {
        type: 'book',
        book_type: 'tarheel',
        id: book_or_tarheel_id
      };
    }
  }
  return null;
};

Button.set_attribute = function(button, attribute, value) {
  emberSet(button, attribute, value);
  var mods = emberGet(button, 'level_modifications');
  if(!mods) { return; }
  var mods = $.extend({}, mods || {});
  for(var key in mods) {
    if(parseInt(key, 10) > 0 && mods[key] && mods[key][attribute] != undefined) {
      mods.override = $.extend({}, mods.override);
      mods.override[attribute] = value;
    }
  }
  emberSet(button, 'level_modifications', mods);
};

Button.extra_actions = function(button) {
  if(button && button.integration && button.integration.action_type == 'webhook') {
    var action_state_id = Math.random();
    var update_state = function(obj) {
     if(!button.get('action_status') || button.get('action_status.state') == action_state_id) {
        if(obj) {
          obj.state = action_state_id;
        }
        button.set('action_status', obj);
        // Necessary to do fast-html caching
        runLater(function() {
          var $button = $(".board[data-id='" + board_id + "']").find(".button[data-id='" + button.get('id') + "']");
          if($button.length) {
            $button.find(".action_container").removeClass('pending').removeClass('errored').removeClass('succeeded');
            if(obj && obj.pending) {
              $button.find(".action_container").addClass('pending');
            } else if(obj && obj.errored) {
              $button.find(".action_container").addClass('errored');
            } else if(obj && obj.completed) {
              $button.find(".action_container").addClass('succeeded');
            }
          }
        }, 100);
        if(obj && (obj.errored || obj.completed)) {
          runLater(function() {
            update_state(null);
          }, 10000);
        }
     }
    };

    if(button.integration.local_url) {
      // Local URLs can be requested by the device, instead of as a webhook
      update_state(null);
      update_state({pending: true});
      var url = button.integration.local_url || "https://www.yahoo.com";
      persistence.ajax(url, {
        type: 'POST',
        data: {
          action: button.integration.action
        }
      }).then(function(res) {
        update_state({completed: true});
      }, function(err) {
        if(err && err._result) { err = err._result; }
        if(err && err.fakeXHR && err.fakeXHR.status === 0) {
          // TODO: create an iframe to do a local form post
          if(!document.getElementById('button_action_post_frame')) {
            var frame = document.createElement('iframe');
            frame.style.position = 'absolute';
            frame.style.left = '-1000px';
            frame.style.top = '10px';
            frame.style.width = '100px';
            frame.sandbox = '';
            frame.id = 'button_action_post_frame';
            frame.name = frame.id;
            document.body.appendChild(frame);
          }
          var form = document.createElement('form');
          form.style.position = 'absolute';
          form.style.left = '-1000px';
          form.action = url;
          form.method = 'POST';
          form.target = 'button_action_post_frame';
          form.id = 'button_action_post';
          var input = document.createElement('input');
          input.type = 'hidden';
          input.name = 'action';
          input.value = button.integration.action;
          form.appendChild(input);
          var btn = document.createElement('button');
          btn.type = 'submit';
          form.appendChild(btn);
          document.body.appendChild(form);
          runLater(function() {
            form.submit();
            update_state({completed: true});
          }, 500);
        } else {
          update_state({errored: true});
        }
      });
    } else {
      var user_id = app_state.get('currentUser.id') || 'nobody';
      var board_id = app_state.get('currentBoardState.id');
      if(user_id && board_id) {
        if(!persistence.get('online')) {
          console.log("button failed because offline");
          update_state({errored: true});
        } else {
          update_state(null);
          update_state({pending: true});
          runLater(function() {
            persistence.ajax('/api/v1/users/' + user_id + '/activate_button', {
              type: 'POST',
              data: {
                board_id: board_id,
                button_id: button.get('id'),
                associated_user_id: app_state.get('referenced_speak_mode_user.id')
              }
            }).then(function(res) {
              if(!res.progress) {
                console.log("button failed because didn't get a progress object");
                update_state({errored: true});
              } else {
                progress_tracker.track(res.progress, function(event) {
                  if(event.status == 'errored') {
                    console.log("button failed because of progress result error");
                    update_state({errored: true});
                  } else if(event.status == 'finished') {
                    if(event.result && event.result.length > 0) {
                      var all_valid = true;
                      var any_code = false;
                      event.result.forEach(function(result) {
                        if(result && result.response_code) {
                          any_code = true;
                          if(result.response_code < 200 || result.response_code >= 300) {
                            all_valid = false;
                          }
                        }
                      });
                      if(!all_valid) {
                        console.log("button failed with error response from notification");
                        update_state({errored: true});
                      } else if(!any_code) {
                        console.log("button failed with no webhook responses recorded");
                        update_state({errored: true});
                      } else {
                        update_state({completed: true});
                      }
                    } else {
                      console.log("button failed with notification failure");
                      update_state({errored: true});
                    }
                  }
                }, {success_wait: 500, error_wait: 1000});
              }
            }, function(err) {
              console.log("button failed because of ajax error");
              update_state({errored: true});
            });
          });
        }
      }
    }
  }
};

window.button_broken_image = Button.broken_image;

export default Button;
