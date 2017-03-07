import Ember from 'ember';
import CoughDrop from '../app';
import boundClasses from './bound_classes';
import app_state from './app_state';
import persistence from './persistence';
import i18n from './i18n';
import stashes from './_stashes';
import progress_tracker from './progress_tracker';

var Button = Ember.Object.extend({
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
    } else if(this.get('url') != null) {
      this.set('buttonAction', 'link');
    } else if(this.get('apps') != null) {
      this.set('buttonAction', 'app');
    } else if(this.get('integration') != null) {
      this.set('buttonAction', 'integration');
    } else {
      this.set('buttonAction', 'talk');
    }
  }.observes('load_board', 'url', 'apps', 'integration', 'video', 'link_disabled'),
  talkAction: function() {
    return this.get('buttonAction') == 'talk';
  }.property('buttonAction'),
  folderAction: function() {
    return this.get('buttonAction') == 'folder';
  }.property('buttonAction'),
  integrationAction: function() {
    return this.get('buttonAction') == 'integration';
  }.property('buttonAction'),
  action_image: function() {
    var path = Ember.templateHelpers.path;
    var action = this.get('buttonAction');
    if(action == 'folder') {
      if(this.get('home_lock')) {
        return path('images/folder_home.png');
      } else {
        return path('images/folder.png');
      }
    } else if(action == 'integration') {
      var state = this.get('action_status') || {};
      if(this.get('integration.action_type') == 'render') {
        return path('images/folder_integration.png');
      } else if(state.pending) {
        return path('images/clock.png');
      } else if(state.errored) {
        return path('images/error.png');
      } else if(state.completed) {
        return path('images/check.png');
      } else {
        return path('images/action.png');
      }
    } else if(action == 'talk') {
      return path('images/talk.png');
    } else if(action == 'link') {
      if(this.get('video.popup')) {
        return path('images/video.svg');
      } else {
        return path('images/link.png');
      }
    } else if(action == 'app') {
      return path('images/app.png');
    } else {
      return path('images/unknown_action.png');
    }
  }.property('buttonAction', 'video.popup', 'home_lock', 'action_status', 'action_status.pending', 'action_status.errored', 'action_status.completed', 'integration.action_type'),
  action_alt: function() {
    var path = Ember.templateHelpers.path;
    var action = this.get('buttonAction');
    if(action == 'folder') {
      return i18n.t('folder', "folder");
    } else if(action == 'talk') {
      return i18n.t('talk', "talk");
    } else if(action == 'link') {
      if(this.get('video.popup')) {
        return i18n.t('video', "video");
      } else {
        return i18n.t('link', "link");
      }
    } else if(action == 'app') {
      return i18n.t('app', "app");
    } else if(action == 'integration') {
      return i18n.t('integration', "integration");
    } else {
      return i18n.t('unknown_action', "unknown action");
    }
  }.property('buttonAction', 'video.popup'),
  youtube_regex: (/(?:https?:\/\/)?(?:www\.)?youtu(?:be\.com\/watch\?(?:.*?&(?:amp;)?)?v=|\.be\/)([\w \-]+)(?:&(?:amp;)?[\w\?=]*)?/),
  video_from_url: function() {
    var url = this.get('url');
    var match = url && url.match(this.youtube_regex);
    var id = match && match[1];
    if(id) {
      if(!this.get('video')) {
        this.set('video', {
          type: 'youtube',
          id: id,
          popup: true,
          start: "",
          end: ""
        });
      } else {
        this.setProperties({
          id: id,
          start: "",
          end: ""
        });
      }
    } else {
      this.set('video', null);
    }
  }.observes('url'),
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
    if(url && !url.match(/^http/)) {
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
  image_holder_style: function() {
    var pos = this.get('positioning');
    if(!pos || !pos.image_height) { return ""; }
    return new Ember.String.htmlSafe("margin-top: " + pos.image_top_margin + "px; vertical-align: top; display: inline-block; width: " + pos.image_square + "px; height: " + pos.image_height + "px; line-height: " + pos.image_height + "px;");
  }.property('positioning'),
  image_style: function() {
    var pos = this.get('positioning');
    if(!pos || !pos.image_height) { return ""; }
    return new Ember.String.htmlSafe("width: 100%; vertical-align: middle; max-height: " + pos.image_square + "px;");
  }.property('positioning'),
  computed_style: function() {
    var pos = this.get('positioning');
    if(!pos) { return new Ember.String.htmlSafe(""); }
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
    return new Ember.String.htmlSafe(str);
  }.property('positioning'),
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
  action_class: function() {
    var res = "action_container ";
    if(this.get('buttonAction')) {
      res = res + this.get('buttonAction') + " ";
    }
    if(this.get('home_lock')) {
      res = res + "home ";
    }
    return res;
  }.property('buttonAction'),
  pending: function() {
    return this.get('pending_image') || this.get('pending_sound');
  }.property('pending_image', 'pending_sound'),
  everything_local: function() {
    if(this.image_id && !this.get('image')) {
      var rec = CoughDrop.store.peekRecord('image', this.image_id);
      if(!rec || !rec.get('isLoaded')) { return false; }
    }
    if(this.sound_id && !this.get('sound')) {
      var rec = CoughDrop.store.peekRecord('sound', this.sound_id);
      if(!rec || !rec.get('isLoaded')) { return false; }
    }
    return true;
  },
  load_image: function() {
    var _this = this;
    var image = CoughDrop.store.peekRecord('image', _this.image_id);
    if(image && (!image.get('isLoaded') || !image.get('best_url'))) { image = null; }
    _this.set('image', image);
    if(!image) {
      if(_this.get('no_lookups')) {
        return Ember.RSVP.reject('no image lookups');
      } else {
        return CoughDrop.store.findRecord('image', _this.image_id).then(function(image) {
          // There was a Ember.run.later of 100ms here, I have no idea why but
          // it seemed like a bad idea so I removed it.
          _this.set('image', image);
          return image.checkForDataURL().then(function() {
            _this.set('local_image_url', image.get('best_url'));
            return Ember.RSVP.resolve(image);
          }, function() {
            _this.set('local_image_url', image.get('best_url'));
            return Ember.RSVP.resolve(image);
          });
        });
      }
    } else {
      _this.set('local_image_url', image.get('best_url'));
      return image.checkForDataURL().then(null, function() { return Ember.RSVP.resolve(image); });
    }
  },
  load_sound: function() {
    var _this = this;
    var sound = CoughDrop.store.peekRecord('sound', _this.sound_id);
    if(sound && (!sound.get('isLoaded') || !sound.get('best_url'))) { sound = null; }
    _this.set('sound', sound);
    if(!sound) {
      if(_this.get('no_lookups')) {
        return Ember.RSVP.reject('no sound lookups');
      } else {
        return CoughDrop.store.findRecord('sound', _this.sound_id).then(function(sound) {
          _this.set('sound', sound);
          return sound.checkForDataURL().then(function() {
            _this.set('local_sound_url', sound.get('best_url'));
            return Ember.RSVP.resolve(sound);
          }, function() {
            _this.set('local_sound_url', sound.get('best_url'));
            return Ember.RSVP.resolve(sound);
          });
        });
      }
    } else {
      _this.set('local_sound_url', sound.get('best_url'));
      return sound.checkForDataURL().then(null, function() { return Ember.RSVP.resolve(sound); });
    }
  },
  findContentLocally: function() {
    var _this = this;
    if((!this.image_id || this.get('local_image_url')) && (!this.sound_id || this.get('local_sound_url'))) {
      return Ember.RSVP.resolve(true);
    }
    this.set('content_status', 'pending');
    return new Ember.RSVP.Promise(function(resolve, reject) {
      var promises = [];
      if(_this.image_id && _this.image_url && persistence.url_cache && persistence.url_cache[_this.image_url]) {
        _this.set('local_image_url', persistence.url_cache[_this.image_url]);
        promises.push(Ember.RSVP.resolve());
      } else if(_this.image_id) {
        promises.push(_this.load_image());
      }
      if(_this.sound_id && _this.sound_url && persistence.url_cache && persistence.url_cache[_this.sound_url]) {
        _this.set('local_sound_url', persistence.url_cache[_this.sound_url]);
        promises.push(Ember.RSVP.resolve());
      } else if(_this.sound_id) {
        promises.push(_this.load_sound());
      }

      Ember.RSVP.all(promises).then(function() {
        _this.set('content_status', 'ready');
        resolve(true);
      }, function(err) {
        if(_this.get('no_lookups')) {
          _this.set('content_status', 'missing');
        } else {
          _this.set('content_status', 'errored');
        }
        resolve(false);
        return Ember.RSVP.resolve();
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
Button.attributes = ['label', 'background_color', 'border_color', 'image_id', 'sound_id', 'load_board', 'hide_label', 'completion'];

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

Button.broken_image = function(image) {
  var fallback = Ember.templateHelpers.path('images/square.svg');
  if(image.src && image.src != fallback && !image.src.match(/^data/)) {
    console.log("bad image url: " + image.src);
    image.rel = image.src;
    image.onerror = "";
    image.src = fallback;
    persistence.find_url(image.src).then(function(data_uri) {
      image.src = data_uri;
    }, function() { });
  }
};

Button.extra_actions = function(button) {
  if(button && button.integration && button.integration.action_type == 'webhook') {
    var user_id = app_state.get('currentUser.id');
    var board_id = app_state.get('currentBoardState.id');
    if(user_id && board_id) {
      var action_state_id = Math.random();
      var update_state = function(obj) {
       if(!button.get('action_status') || button.get('action_status.state') == action_state_id) {
          if(obj) {
            obj.state = action_state_id;
          }
          button.set('action_status', obj);
          if(obj && (obj.errored || obj.completed)) {
            Ember.run.later(function() {
              update_state(null);
            }, 10000);
          }
       }
      };
      if(!persistence.get('online')) {
        console.log("button failed because offline");
        update_state({errored: true});
      } else {
        update_state(null);
        update_state({pending: true});
        Ember.run.later(function() {
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
};

window.button_broken_image = Button.broken_image;

export default Button;
