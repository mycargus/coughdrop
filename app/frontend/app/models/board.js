import Ember from 'ember';
import { later as runLater } from '@ember/runloop';
import RSVP from 'rsvp';
import $ from 'jquery';
import DS from 'ember-data';
import CoughDrop from '../app';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';
import modal from '../utils/modal';
import app_state from '../utils/app_state';
import Button from '../utils/button';
import editManager from '../utils/edit_manager';
import boundClasses from '../utils/bound_classes';
import Utils from '../utils/misc';
import { htmlSafe } from '@ember/string';

CoughDrop.Board = DS.Model.extend({
  didLoad: function() {
    this.checkForDataURL().then(null, function() { });
    this.check_for_copy();
    this.clean_license();
  },
  didUpdate: function() {
    this.set('fetched', false);
  },
  name: DS.attr('string'),
  key: DS.attr('string'),
  description: DS.attr('string'),
  created: DS.attr('date'),
  updated: DS.attr('date'),
  user_name: DS.attr('string'),
  locale: DS.attr('string'),
  translated_locales: DS.attr('raw'),
  full_set_revision: DS.attr('string'),
  current_revision: DS.attr('string'),
  for_user_id: DS.attr('string'),
  copy_id: DS.attr('string'),
  source_id: DS.attr('string'),
  image_urls: DS.attr('raw'),
  sound_urls: DS.attr('raw'),
  translations: DS.attr('raw'),
  categories: DS.attr('raw'),
  home_board: DS.attr('boolean'),
  valid_id: function() {
    return !!(this.get('id') && this.get('id') != 'bad');
  }.property('id'),
  could_be_in_use: function() {
    // no longer using (this.get('public') && this.get('brand_new'))
    return this.get('non_author_uses') > 0 || this.get('non_author_starred');
  }.property('non_author_uses', 'public', 'brand_new', 'stars'),
  definitely_in_use: function() {
    return this.get('non_author_uses') > 0 || this.get('stars') > 0;
  }.property('non_author_uses', 'stars'),
  fallback_image_url: "https://s3.amazonaws.com/opensymbols/libraries/arasaac/board_3.png",
  key_placeholder: function() {
    var key = (this.get('name') || "my-board").replace(/^\s+/, '').replace(/\s+$/, '');
    var ref = key;
    while(key.length < 4) {
      key = key + ref;
    }
    key = key.toLowerCase().replace(/[^a-zA-Z0-9_-]+/g, '-').replace(/-+$/, '').replace(/-+/g, '-');
    return key;
  }.property('name'),
  icon_url_with_fallback: function() {
    // TODO: way to fall back to something other than a broken image when disconnected
    if(persistence.get('online')) {
      return this.get('image_data_uri') || this.get('image_url') || this.fallback_image_url;
    } else {
      return this.get('image_data_uri') || this.fallback_image_url;
    }
  }.property('image_url'),
  shareable: function() {
    return this.get('public') || this.get('permissions.edit');
  }.property('public', 'permissions.edit'),
  used_buttons: function() {
    var result = [];
    var grid = this.get('grid');
    var buttons = this.get('buttons');
    if(!grid || !buttons) { return []; }
    for(var idx = 0; idx < grid.order[0].length; idx++) {
      for(var jdx = 0; jdx < grid.order.length; jdx++) {
        var id = grid.order[jdx][idx];
        if(id) {
          var button = null;
          for(var kdx = 0; kdx < buttons.length; kdx++) {
            if(buttons[kdx].id == id) {
              result.push(buttons[kdx]);
            }
          }
        }
      }
    }
    return result;
  }.property('buttons', 'grid'),
  labels: function() {
    var list = [];
    this.get('used_buttons').forEach(function(button) {
      if(button && button.label) {
        list.push(button.label);
      }
    });
    return list.join(', ');
  }.property('buttons', 'grid'),
  copy_version: function() {
    var key = this.get('key');
    if(key.match(/_\d+$/)) {
      return key.split(/_/).pop();
    } else {
      return null;
    }
  }.property('key'),
  nothing_visible: function() {
    var found_visible = false;
    this.get('used_buttons').forEach(function(button) {
      if(button && !button.hidden) {
        found_visible = true;
      }
    });
    return !found_visible;
  }.property('buttons', 'grid'),
  map_image_urls: function(map) {
    map = map || {};
    var res = [];
    var locals = this.get('local_images_with_license');
    var local_map = this.get('image_urls') || {};
    this.get('used_buttons').forEach(function(button) {
      if(button && button.image_id) {
        if(local_map[button.image_id]) {
          res.push({id: button.image_id, url: local_map[button.image_id]});
        } else if(map[button.image_id]) {
          res.push({id: button.image_id, url: map[button.image_id]});
        } else {
          var img = locals.find(function(l) { return l.get('id') == button.image_id; });
          if(img) {
            res.push({id: button.image_id, url: img.get('url')});
          } else {
            res.some_missing = true;
          }
        }
      }
    });
    return res;
  },
  local_images_with_license: function() {
    var images = CoughDrop.store.peekAll('image');
    var result = [];
    var missing = false;
    this.get('used_buttons').forEach(function(button) {
      if(button && button.image_id) {
        var image = images.findBy('id', button.image_id.toString());
        if(image) {
          result.push(image);
        } else {
//          console.log('missing image ' + button.image_id);
          missing = true;
        }
      }
    });
    result = result.uniq();
    result.some_missing = missing;
    return result;
  }.property('grid', 'buttons'),
  map_sound_urls: function(map) {
    map = map || {};
    var res = [];
    var locals = this.get('local_sounds_with_license');
    var local_map = this.get('sound_urls') || {};
    this.get('used_buttons').forEach(function(button) {
      if(button && button.sound_id) {
        if(local_map[button.sound_id]) {
          res.push({id: button.sound_id, url: local_map[button.sound_id]});
        } else if(map[button.sound_id]) {
          res.push({id: button.sound_id, url: map[button.sound_id]});
        } else {
          var snd = locals.find(function(l) { return l.get('id') == button.sound_id; });
          if(snd) {
            res.push({id: button.sound_id, url: snd.get('url')});
          } else {
            res.some_missing = true;
          }
        }
      }
    });
    return res;
  },
  local_sounds_with_license: function() {
    var sounds = CoughDrop.store.peekAll('sound');
    var result = [];
    var missing = false;
    this.get('used_buttons').forEach(function(button) {
      if(button && button.sound_id) {
        var sound = sounds.findBy('id', button.sound_id.toString());
        if(sound) {
          result.push(sound);
        } else {
//          console.log('missing sound ' + button.sound_id);
          missing = true;
        }
      }
    });
    result = result.uniq();
    result.some_missing = missing;
    return result;
  }.property('grid', 'buttons'),
  levels: function() {
    return this.get('buttons').filter(function(b) { return b.level_modifications; }).length > 0;
  }.property('buttons@each.level_modifications'),
  without_lookups: function(callback) {
    this.set('no_lookups', true);
    callback();
    this.set('no_lookups', false);
  },
  locales: function() {
    var res = [];
    var button_ids = (this.get('translations') || {});
    var all_langs = [];
    for(var button_id in button_ids) {
      if(typeof button_ids[button_id] !== 'string') {
        var keys = Object.keys(button_ids[button_id] || {});
        all_langs = all_langs.concat(keys);
      }
    }
    all_langs.forEach(function(lang) {
      if(res.indexOf(lang) == -1) {
        res.push(lang);
      }
    });
    return res;
  }.property('translations'),
  translations_for_button: function(button_id) {
    // necessary otherwise button that wasn't translated at first will never be translatable
    var trans = (this.get('translations') || {})[button_id] || {};
    (this.get('locales') || []).forEach(function(locale) {
      trans[locale] = trans[locale] || {};
    });
    return trans;
  },
  translated_buttons: function(label_locale, vocalization_locale) {
    var res = [];
    var trans = this.get('translations') || {};
    var buttons = this.get('buttons') || [];
    if(!trans) { return buttons; }
    label_locale = label_locale || trans.current_label || this.get('locale') || 'en';
    vocalization_locale = vocalization_locale || trans.current_vocalization || this.get('locale') || 'en';
    if(trans.current_label == label_locale && trans.current_vocalization == vocalization_locale) { return buttons; }
    buttons.forEach(function(button) {
      var b = $.extend({}, button);
      if(trans[b.id]) {
        if(trans[b.id][label_locale] && trans[b.id][label_locale].label) {
          b.label = trans[b.id][label_locale].label;
        }
        if(trans[b.id][vocalization_locale] && (trans[b.id][vocalization_locale].vocalization || trans[b.id][vocalization_locale].label)) {
          b.vocalization = (trans[b.id][vocalization_locale].vocalization || trans[b.id][vocalization_locale].label);
        }
      }
      res.push(b);
    });
    return res;
  },
  different_locale: function() {
    var current = (navigator.language || 'en').split(/[-_]/)[0];
    return current != this.get('shortened_locale');
  }.property('shortened_locale'),
  shortened_locale: function() {
    var res = (this.get('locale') || 'en').split(/[-_]/)[0];
    if((this.get('translated_locales') || []).length > 1) { res = res + "+"; }
    return res;
  }.property('locale', 'translated_locales'),
  find_content_locally: function() {
    var _this = this;
    var fetch_promise = this.get('fetch_promise');
    if(this.get('fetched')) { return RSVP.resolve(); }
    if(fetch_promise) { return fetch_promise; }

    if(this.get('no_lookups')) {
      // we don't need to wait on this for an aggressive local load
      return RSVP.resolve(true);
    }

    var promises = [];
    var image_ids = [];
    var sound_ids = [];
    (this.get('buttons') || []).forEach(function(btn) {
      if(btn.image_id) {
        image_ids.push(btn.image_id);
      }
      if(btn.sound_id) {
        sound_ids.push(btn.sound_id);
      }
    });
    promises.push(persistence.push_records('image', image_ids));
    promises.push(persistence.push_records('sound', sound_ids));

    fetch_promise = RSVP.all_wait(promises).then(function() {
      _this.set('fetched', true);
      fetch_promise = null;
      _this.set('fetch_promise', null);
      return true;
    }, function() {
      fetch_promise = null;
      _this.set('fetch_promise', null);
    });
    _this.set('fetch_promise', fetch_promise);
    return fetch_promise;
  },
  set_all_ready: function() {
    var allReady = true;
    if(!this.get('pending_buttons')) { return; }
    this.get('pending_buttons').forEach(function(b) {
      if(b.get('content_status') != 'ready' && b.get('content_status') != 'errored') { allReady = false; }
    });
    this.set('all_ready', allReady);
  }.observes('pending_buttons', 'pending_buttons.[]', 'pending_buttons.@each.content_status'),
  prefetch_linked_boards: function() {
    var boards = this.get('linked_boards');
    runLater(function() {
      var board_ids = [];
      boards.forEach(function(b) { if(b.id) { board_ids.push(b.id); } });
      persistence.push_records('board', board_ids).then(function(boards_hash) {
        for(var idx in boards_hash) {
          if(idx && boards_hash[idx]) {
//            boards_hash[idx].find_content_locally();
          }
        }
      }, function() { });
    }, 500);
  },
  clean_license: function() {
    var _this = this;
    ['copyright_notice', 'source', 'author'].forEach(function(key) {
      if(_this.get('license.' + key + '_link')) {
        _this.set('license.' + key + '_url', _this.get('license.' + key + '_url') || _this.get('license.' + key + '_link'));
      }
      if(_this.get('license.' + key + '_link')) {
        _this.set('license.' + key + '_link', _this.get('license.' + key + '_link') || _this.get('license.' + key + '_url'));
      }
    });
  },
  linked_boards: function() {
    var buttons = this.get('buttons') || [];
    var result = [];
    for(var idx = 0; idx < buttons.length; idx++) {
      if(buttons[idx].load_board) {
        var board = buttons[idx].load_board;
        if(buttons[idx].link_disabled) {
          board.link_disabled = true;
        }
        result.push(board);
      }
    }
    return Utils.uniq(result, function(r) { return r.id; });
  }.property('buttons'),
  unused_buttons: function() {
    var unused = [];
    var grid = this.get('grid');
    var button_ids = [];
    if(grid && grid.order) {
      for(var idx = 0; idx < grid.order.length; idx++) {
        if(grid.order[idx]) {
          for(var jdx = 0; jdx < grid.order[idx].length; jdx++) {
            button_ids.push(grid.order[idx][jdx]);
          }
        }
      }
    }
    var buttons = this.get('buttons');
    buttons.forEach(function(button) {
      if(button_ids.indexOf(button.id) == -1) {
        unused.push(button);
      }
    });
    return unused;
  }.property('buttons', 'grid', 'grid.order'),
  long_preview: function() {
    var date = Ember.templateHelpers.date(this.get('created'), 'day');
    var labels = this.get('labels');
    if(labels && labels.length > 100) {
      var new_labels = "";
      var ellipsed = false;
      labels.split(/, /).forEach(function(l) {
        if(new_labels.length === 0) {
          new_labels = l;
        } else if(new_labels.length < 75) {
          new_labels = new_labels + ", " + l;
        } else if(!ellipsed) {
          ellipsed = true;
          new_labels = new_labels + "...";
        }
      });
      labels = new_labels;
    }
    return this.get('key') + " (" + date + ") - " + this.get('user_name') + " - " + labels;
  }.property('name', 'labels', 'user_name', 'created'),
  search_string: function() {
    return this.get('name') + " " + this.get('user_name') + " " + this.get('labels');
  }.property('name', 'labels', 'user_name'),
  parent_board_id: DS.attr('string'),
  parent_board_key: DS.attr('string'),
  link: DS.attr('string'),
  image_url: DS.attr('string'),
  buttons: DS.attr('raw'),
  grid: DS.attr('raw'),
  license: DS.attr('raw'),
  images: DS.hasMany('image'),
  permissions: DS.attr('raw'),
  copy: DS.attr('raw'),
  copies: DS.attr('number'),
  original: DS.attr('raw'),
  word_suggestions: DS.attr('boolean'),
  public: DS.attr('boolean'),
  visibility: DS.attr('string'),
  brand_new: DS.attr('boolean'),
  protected: DS.attr('boolean'),
  protected_settings: DS.attr('raw'),
  non_author_uses: DS.attr('number'),
  using_user_names: DS.attr('raw'),
  downstream_boards: DS.attr('number'),
  downstream_board_ids: DS.attr('raw'),
  immediately_upstream_boards: DS.attr('number'),
  unlinked_buttons: DS.attr('number'),
  forks: DS.attr('number'),
  total_buttons: DS.attr('number'),
  shared_users: DS.attr('raw'),
  sharing_key: DS.attr('string'),
  starred: DS.attr('boolean'),
  stars: DS.attr('number'),
  non_author_starred: DS.attr('boolean'),
  star_or_unstar: function(star) {
    var _this = this;
    console.log(star);
    persistence.ajax('/api/v1/boards/' + this.get('id') + '/stars', {
      type: 'POST',
      data: {
        '_method': (star ? 'POST' : 'DELETE')
      }
    }).then(function(data) {
      _this.set('starred', data.starred);
      _this.set('stars', data.stars);
    }, function() {
      modal.warning(i18n.t('star_failed', "Like action failed"));
    });
  },
  star: function() {
    return this.star_or_unstar(true);
  },
  unstar: function() {
    return this.star_or_unstar(false);
  },
  embed_code: function() {
    return "<iframe src=\"" + this.get('link') + "?embed=1\" frameborder=\"0\" style=\"min-width: 640px; min-height: 480px;\"><\\iframe>";

  }.property('link'),
  check_for_copy: function() {
    // TODO: check local records for a user-specific copy as a fallback in case
    // offline
  },
  multiple_copies: function() {
    return this.get('copies') > 1;
  }.property('copies'),
  create_copy: function(user, make_public) {
    var board = CoughDrop.store.createRecord('board', {
      parent_board_id: this.get('id'),
      key: this.get('key').split(/\//)[1],
      name: this.get('copy_name') || this.get('name'),
      description: this.get('description'),
      image_url: this.get('image_url'),
      license: this.get('license'),
      word_suggestions: this.get('word_suggestions'),
      public: (make_public || false),
      buttons: this.get('buttons'),
      grid: this.get('grid'),
      locale: this.get('locale'),
      for_user_id: (user && user.get('id')),
      translations: this.get('translations')
    });
    this.set('copy_name', null);
    var _this = this;
    var res = board.save();
    res.then(function() {
      _this.rollbackAttributes();
    }, function() { });
    return res;
  },
  add_button: function(button) {
    var buttons = this.get('buttons') || [];
    var new_button = $.extend({}, button.raw());
    new_button.id = button.get('id');
    var collision = false;
    var max_id = 0;
    for(var idx = 0; idx < buttons.length; idx++) {
      if(buttons[idx].id == new_button.id) {
        collision = true;
      }
      max_id = Math.max(max_id, parseInt(buttons[idx].id, 10));
    }
    if(collision || !new_button.id) {
      new_button.id = max_id + 1;
    }
    buttons.push(new_button);
    var grid = this.get('grid');
    var placed = false;
    if(grid && grid.order) {
      for(var idx = 0; idx < grid.order.length; idx++) {
        if(grid.order[idx]) {
          for(var jdx = 0; jdx < grid.order[idx].length; jdx++) {
            if(!grid.order[idx][jdx] && !placed) {
              grid.order[idx][jdx] = new_button.id;
              placed = true;
            }
          }
        }
      }
      this.set('grid', $.extend({}, grid));
    }
    this.set('buttons', [].concat(buttons));
    return new_button.id;
  },
  reload_including_all_downstream: function(affected_board_ids) {
    affected_board_ids = affected_board_ids || [];
    if(affected_board_ids.indexOf(this.get('id')) == -1) {
      affected_board_ids.push(this.get('id'));
    }
    var found_board_ids = [];
    // when a board is copied, we need to reload all the original versions,
    // so if any of them are in-memory or in indexeddb, then we need to
    // reload or fetch them remotely to get the latest, updated version,
    // which will include the "my copy" information.
    CoughDrop.store.peekAll('board').map(function(i) { return i; }).forEach(function(brd) {
      if(brd && affected_board_ids && affected_board_ids.indexOf(brd.get('id')) != -1) {
        if(!brd.get('isLoading') && !brd.get('isNew') && !brd.get('isDeleted')) {
          brd.reload(true);
        }
        found_board_ids.push(brd.get('id'));
      }
    });
    affected_board_ids.forEach(function(id) {
      if(found_board_ids.indexOf(id) == -1) {
        persistence.find('board', id).then(function() {
          CoughDrop.store.findRecord('board', id).then(null, function() { });
        }, function() { });
      }
    });
  },
  button_visible: function(button_id) {
    var grid = this.get('grid');
    if(!grid || !grid.order) { return false; }
    for(var idx = 0; idx < grid.order.length; idx++) {
      if(grid.order[idx]) {
        for(var jdx = 0; jdx < grid.order[idx].length; jdx++) {
          if(grid.order[idx][jdx] == button_id) {
            return true;
          }
        }
      }
    }
    return false;
  },
  checkForDataURL: function() {
    this.set('checked_for_data_url', true);
    var url = this.get('icon_url_with_fallback');
    var _this = this;
    if(!this.get('image_data_uri') && url && url.match(/^http/)) {
      return persistence.find_url(url, 'image').then(function(data_uri) {
        _this.set('image_data_uri', data_uri);
        return _this;
      });
    } else if(url && url.match(/^data/)) {
      return RSVP.resolve(this);
    }
    return RSVP.reject('no board data url');
  },
  checkForDataURLOnChange: function() {
    this.checkForDataURL().then(null, function() { });
  }.observes('image_url'),
  for_sale: function() {
    if(this.get('protected')) {
      var settings = this.get('protected_settings') || {};
      if(settings.cost) {
        return true;
      } else if(settings.root_board) {
        return true;
      }
    }
    return false;
  }.property('protected', 'protected_settings'),
  protected_material: function() {
    var protect = !!this.get('protected');
    if(protect) { return true; }
    (this.get('local_images_with_license') || []).forEach(function(image) {
      if(image && image.get('protected')) {
        protect = true;
      }
    });
    if(protect) { return true; }
    (this.get('local_sounds_with_license') || []).forEach(function(sound) {
      if(sound && sound.get('protected')) {
        protect = true;
      }
    });
    return !!protect;
  }.property('protected', 'local_images_with_license', 'local_sounds_with_license'),
  protected_sources: function() {
    var res = {};
    if(this.get('protected_material')) {
      if(this.get('protected_settings.media')) {
        (this.get('protected_settings.media_sources') || ['lessonpix']).forEach(function(key) {
          res[key] = true;
        });
      }
      if(this.get('protected_settings.vocabulary')) {
        res.board = true;
      }
    }
    res.list = Object.keys(res);
    return res;
  }.property('protected_material', 'protected_settings'),
  load_button_set: function(force) {
    var _this = this;
    if(this.get('button_set') && !force) {
      return RSVP.resolve(this.get('button_set'));
    }
    if(!this.get('id')) { return; }
    var button_set = CoughDrop.store.peekRecord('buttonset', this.get('id'));
    if(button_set && !force) {
      this.set('button_set', button_set);
      return RSVP.resolve(button_set);
    } else {
      var valid_button_set = null;
      var button_sets = CoughDrop.store.peekAll('buttonset').map(function(i) { return i; }).forEach(function(bs) {
        if(bs && (bs.get('board_ids') || []).indexOf(_this.get('id')) != -1) {
          if(bs.get('fresh') || !valid_button_set) {
            valid_button_set = bs;
          }
        }
      });
      if(valid_button_set && !force) {
        if(!_this.get('fresh') || valid_button_set.get('fresh')) {
          _this.set('button_set', valid_button_set);
          return RSVP.resolve(valid_button_set);
        } else{
        }
      }
      // first check if there's a satisfactory higher-level buttonset that can be used instead
      var res = CoughDrop.store.findRecord('buttonset', this.get('id')).then(function(button_set) {
        _this.set('button_set', button_set);
        if((_this.get('fresh') || force) && !button_set.get('fresh')) {
          return button_set.reload();
        } else {
          return button_set;
        }
      });
      res.then(null, function() { });
      return res;
    }
  },
  add_classes: function() {
    if(this.get('classes_added')) { return; }
    (this.get('buttons') || []).forEach(function(button) {
      boundClasses.add_rule(button);
      boundClasses.add_classes(button);
    });
    this.set('classes_added', true);
  },
  render_fast_html: function(size) {
    CoughDrop.log.track('redrawing');

    var buttons = this.translated_buttons(app_state.get('label_locale'), app_state.get('vocalization_locale'));
    var grid = this.get('grid');
    var ob = [];
    for(var idx = 0; idx < grid.rows; idx++) {
      var row = [];
      for(var jdx = 0; jdx < grid.columns; jdx++) {
        var found = false;
        for(var kdx = 0; kdx < buttons.length; kdx++) {
          if(buttons[kdx] && buttons[kdx].id && buttons[kdx].id == (grid.order[idx] || [])[jdx]) {
            found = true;
            var btn = $.extend({}, buttons[kdx]);
            row.push(btn);
          }
        }
        if(!found) {
          row.push({
            empty: true,
            label: '',
            id: -1
          });
        }
      }
      ob.push(row);
    }

    var starting_height = Math.floor((size.height / (grid.rows || 2)) * 100) / 100;
    var starting_width = Math.floor((size.width / (grid.columns || 2)) * 100) / 100;
    var extra_pad = size.extra_pad;
    var inner_pad = size.inner_pad;
    var double_pad = inner_pad * 2;
    var radius = 4;
    var context = null;

    var currentLabelHeight = size.base_text_height - 3;
    this.set('text_size', 'normal');
    if(starting_height < 35) {
      this.set('text_size', 'really_small_text');
    } else if(starting_height < 75) {
      this.set('text_size', 'small_text');
    }

    var _this = this;

    var button_html = function(button, pos) {
      var res = "";
      // TODO: sanitize all these for safety?

      var local_image_url = persistence.url_cache[(_this.get('image_urls') || {})[button.image_id] || 'none'] || (_this.get('image_urls') || {})[button.image_id] || 'none';
      var local_sound_url = persistence.url_cache[(_this.get('sound_urls') || {})[button.sound_id] || 'none'] || (_this.get('sound_urls') || {})[button.sound_id] || 'none';
      var opts = Button.button_styling(button, _this, pos);

      res = res + "<div style='" + opts.button_style + "' class='" + opts.button_class + "' data-id='" + button.id + "' tabindex='0'>";
      res = res + "<div class='" + opts.action_class + "'>";
      res = res + "<span class='action'>";
      res = res + "<img src='" + opts.action_image + "' alt='" + opts.action_alt + "' />";
      res = res + "</span>";
      res = res + "</div>";

      res = res + "<span style='" + opts.image_holder_style + "'>";
      if(!app_state.get('currentUser.hide_symbols') && local_image_url && local_image_url != 'none') {
        res = res + "<img src=\"" + Button.clean_url(local_image_url) + "\" onerror='button_broken_image(this);' style='" + opts.image_style + "' class='symbol' />";
      }
      res = res + "</span>";
      if(button.sound_id && local_sound_url && local_sound_url != 'none') {
        var rel_url = Button.clean_url(_this.get('sound_urls')[button.sound_id]);
        var url = Button.clean_url(local_sound_url);
        res = res + "<audio style='display: none;' preload='auto' src=\"" + url + "\" rel=\"" + rel_url + "\"></audio>";
      }
      res = res + "<div class='" + size.button_symbol_class + "'>";
      res = res + "<span class='button-label " + (button.hide_label ? "hide-label" : "") + "'>" + opts.label + "</span>";
      res = res + "</div>";

      res = res + "</div>";
      return res;
    };
    var html = "";

    var text_position = "text_position_" + (app_state.get('currentUser.preferences.device.button_text_position') || window.user_preferences.device.button_text_position);

    CoughDrop.log.track('computing dimensions');
    ob.forEach(function(row, i) {
      html = html + "\n<div class='button_row fast'>";
      row.forEach(function(button, j) {
        boundClasses.add_rule(button);
        if(size.display_level && button.level_modifications) {
          if(size.display_level == _this.get('default_level')) {
          } else {
            var mods = button.level_modifications;
            var level = size.display_level;
            console.log("mods at", mods, level);
            if(mods.pre) {
              for(var key in mods.pre) {
                button[key] = mods.pre[key];
              }
            }
            for(var idx = 1; idx <= level; idx++) {
              if(mods[idx]) {
                for(var key in mods[idx]) {
                  button[key] = mods[idx][key];
                }
              }
            }
          }
        }
        boundClasses.add_classes(button);
        var button_height = starting_height - (extra_pad * 2);
        var button_width = starting_width - (extra_pad * 2);
        var top = extra_pad + (i * starting_height) + inner_pad;
        var left = extra_pad + (j * starting_width) + inner_pad;

        var image_height = button_height - currentLabelHeight - CoughDrop.boxPad - (inner_pad * 2) + 8;
        var image_width = button_width - CoughDrop.boxPad - (inner_pad * 2) + 8;

        var top_margin = currentLabelHeight + CoughDrop.labelHeight - 8;
        if(_this.get('text_size') == 'really_small_text') {
          if(currentLabelHeight > 0) {
            image_height = image_height + currentLabelHeight - CoughDrop.labelHeight + 25;
            top_margin = 0;
          }
        } else if(_this.get('text_size') == 'small_text') {
          if(currentLabelHeight > 0) {
            image_height = image_height + currentLabelHeight - CoughDrop.labelHeight + 10;
            top_margin = top_margin - 10;
          }
        }
        if(button_height < 50) {
          image_height = image_height + (inner_pad * 2);
        }
        if(button_width < 50) {
          image_width = image_width + (inner_pad * 2) + (extra_pad * 2);
        }
        if(currentLabelHeight === 0 || text_position != 'text_position_top') {
          top_margin = 0;
        }

        html = html + button_html(button, {
          top: top,
          left: left - inner_pad - inner_pad - inner_pad,
          width: button_width,
          height: button_height,
          image_height: image_height,
          image_width: image_width,
          image_square: Math.min(image_height, image_width),
          image_top_margin: top_margin,
          border: inner_pad
        });
      });
      html = html + "\n</div>";
    });
    return {
      width: size.width,
      height: size.height,
      revision: _this.get('current_revision'),
      html: htmlSafe(html)
    };
  }
});

CoughDrop.Board.reopenClass({
  clear_fast_html: function() {
    CoughDrop.store.peekAll('board').forEach(function(b) {
      b.set('fast_html', null);
    });
    if(app_state.get('currentBoardState.id') && editManager.controller && !editManager.controller.get('ordered_buttons')) {
      editManager.process_for_displaying();
    }
  },
  refresh_data_urls: function() {
    // when you call sync, you're potentially prefetching a bunch of images and
    // sounds that don't have a locally-stored copy yet, so their data-uris will
    // all come up empty. But then if you open one of those boards without
    // refreshing the page, they're stored in the ember-data cache without a
    // data-uri so they fail if you go offline, even though they actually
    // got persisted to the local store. This method tried to address that
    // shortcoming.
    var _this = this;
    runLater(function() {
      CoughDrop.store.peekAll('board').map(function(i) { return i; }).forEach(function(i) {
        if(i) {
          i.checkForDataURL().then(null, function() { });
        }
      });
      CoughDrop.store.peekAll('image').map(function(i) { return i; }).forEach(function(i) {
        if(i) {
          i.checkForDataURL().then(null, function() { });
        }
      });
      CoughDrop.store.peekAll('sound').map(function(i) { return i; }).forEach(function(i) {
        if(i) {
          i.checkForDataURL().then(null, function() { });
        }
      });
    });
  },
  mimic_server_processing: function(record, hash) {
    if(hash.board.id.match(/^tmp/)) {
      var splits = (hash.board.key || hash.board.id).split(/\//);
      var key = splits[1] || splits[0];
      var rnd = "tmp_" + Math.round(Math.random() * 10000).toString() + (new Date()).getTime().toString();
      hash.board.key = rnd + "/" + key;
    }
    hash.board.permissions = {
      "view": true,
      "edit": true
    };

    hash.board.buttons = hash.board.buttons || [];
    delete hash.board.images;
    hash.board.grid = {
      rows: (hash.board.grid && hash.board.grid.rows) || 2,
      columns: (hash.board.grid && hash.board.grid.columns) || 4,
      order: (hash.board.grid && hash.board.grid.order) || []
    };
    for(var idx = 0; idx < hash.board.grid.rows; idx++) {
      hash.board.grid.order[idx] = hash.board.grid.order[idx] || [];
      for(var jdx = 0; jdx < hash.board.grid.columns; jdx++) {
        hash.board.grid.order[idx][jdx] = hash.board.grid.order[idx][jdx] || null;
      }
      if(hash.board.grid.order[idx].length > hash.board.grid.columns) {
        hash.board.grid.order[idx] = hash.board.grid.order[idx].slice(0, hash.board.grid.columns);
      }
    }
    if(hash.board.grid.order.length > hash.board.grid.rows) {
      hash.board.grid.order = hash.board.grid.order.slice(0, hash.board.grid.rows);
    }
    return hash;
  }
});

export default CoughDrop.Board;
