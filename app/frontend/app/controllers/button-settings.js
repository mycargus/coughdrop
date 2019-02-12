import Ember from 'ember';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import { later as runLater } from '@ember/runloop';
import $ from 'jquery';
import modal from '../utils/modal';
import editManager from '../utils/edit_manager';
import contentGrabbers from '../utils/content_grabbers';
import stashes from '../utils/_stashes';
import i18n from '../utils/i18n';
import CoughDrop from '../app';
import utterance from '../utils/utterance';
import capabilities from '../utils/capabilities';
import app_state from '../utils/app_state';
import persistence from '../utils/persistence';
import boundClasses from '../utils/bound_classes';
import Button from '../utils/button';
import Utils from '../utils/misc';

export default modal.ModalController.extend({
  opening: function() {
    var button = this.get('model.button');
    button.load_image();
    button.load_sound();
    this.set('board', this.get('model.board'));
    this.set('last_values', null);
    this.set('model', button);
    button.set('translations_hash', this.get('board').translations_for_button(button.id));
    this.set('handle_updates', true);
    contentGrabbers.setup(button, this);

    contentGrabbers.check_for_dropped_file();
    var state = button.state || 'general';
    if(!app_state.get('currentUser.preferences.disable_button_help')) {
      state = 'help';
      this.set('auto_help', true);
    }
    if(!button.get('level_style')) {
      if(!button.get('level_modifications') || Object.keys(button.get('level_modifications')).length == 0) {
        button.set('level_style', 'none');
      } else {
        var mods = button.get('level_modifications');
        var json = {};
        var hidden_level = null, link_disabled_level = null;
        var advanced = false;
        var strip = function(list) { return list.filter(function(k) { return k != 'hidden' && k != 'link_disabled'; }) };
        for(var idx in mods) {
          if(idx == 'pre') {
            var keys = Object.keys(mods[idx]).sort();
            var extra_keys = strip(keys);
            if(extra_keys.length > 0) {
              advanced = true;
            } else if(mods[idx]['hidden'] != undefined && mods[idx]['hidden'] != true) {
              advanced = true;
            } else if(mods[idx]['link_disabled'] != undefined & mods[idx]['link_disabled'] != true) {
              advanced = true;
            }
            if(advanced) { json[idx] = mods[idx]; }
          } else if(parseInt(idx, 10) > 0) {
            var keys = Object.keys(mods[idx]).sort();
            var extra_keys = strip(keys);
            if(extra_keys.length > 0) {
              advanced = true;
            } else if(mods[idx]['hidden'] != undefined && (hidden_level || mods[idx]['hidden'] !== false)) {
              advanced = true;
            } else if(mods[idx]['link_disabled'] != undefined && (link_disabled_level || mods[idx]['link_disabled'] !== false)) {
              advanced = true;
            } else if(mods[idx]['hidden'] === false) {
              hidden_level = parseInt(idx, 10);
            } else if(mods[idx]['link_disabled'] === false) {
              link_disabled_level = parseInt(idx, 10);
            }
            if(advanced) { json[idx] = mods[idx]; }
          }
        }
        if(advanced) {
          button.set('level_style', 'advanced');
          button.set('level_json', JSON.stringify(json, null, 2));
        } else if(hidden_level || link_disabled_level) {
          button.set('level_style', 'basic');
          button.set('hidden_level', hidden_level);
          button.set('link_disabled_level', link_disabled_level);
        } else {
          button.set('level_style', 'none');
        }
      }
    }

    this.set('state', state);
    this.set('original_image_license', $.extend({}, button.get('image.license')));
    this.set('original_sound_license', $.extend({}, button.get('sound.license')));

    var fallback = 'personal';
    if(this.get('board.user_name') != app_state.get('currentUser.user_name')) {
      fallback = 'current_user';
    }
    this.set('board_search_type', stashes.get('last_board_search_type') || fallback);
    if(!(stashes.get('last_image_library') || "").match(/required/)) {
      this.set('image_library', stashes.get('last_image_library'));
    } else if(app_state.get('currentUser.preferences.preferred_symbols')) {
      this.set('image_library', app_state.get('currentUser.preferences.preferred_symbols'));
    }
    this.set('model.image_field', this.get('model.label'));

    var supervisees = [];
    this.set('has_supervisees', app_state.get('sessionUser.supervisees.length') > 0);
    var _this = this;
    _this.set('premium_symbols', app_state.get('currentUser.subscription.extras_enabled'));
    _this.set('lessonpix_enabled', false);
    var find_integration = null;
    if(this.get('board.user_name') == app_state.get('currentUser.user_name')) {
      find_integration = app_state.get('currentUser').find_integration('lessonpix');
    } else {
      find_integration = CoughDrop.User.find_integration(this.get('board.user_name'), 'lessonpix').then(null, function() {
        return app_state.get('currentUser').find_integration('lessonpix');
      });
    }
    find_integration.then(function(res) {
      _this.set('lessonpix_enabled', true);
      if(stashes.get('last_image_library') == 'lessonpix') {
        runLater(function() {
          _this.set('image_library', 'lessonpix');
        });
      }
    }, function(err) {
      if(stashes.get('last_image_library') == 'lessonpix') {
        _this.set('image_library', null);
      }
    });
  },
  closing: function() {
    stashes.set('last_board_search_type', this.get('board_search_type'));
//    editManager.done_editing_image();
    contentGrabbers.clear();
  },
  labelChanged: function() {
    if(!this.get('handle_updates')) { return; }
    editManager.change_button(this.get('model.id'), {
      label: this.get('model.label')
    });
  }.observes('model.label'),
  update_hidden: function(obj, attr) {
    var hash = {'model.hidden': 'hidden', 'model.link_disabled': 'link_disabled'};
    var ref = hash[attr];
    var vals = this.get('last_values') || {};
    if(this.get('model.id') && ref) {
      var mod = vals[this.get('model.id')] || {};
      if(mod[ref] == undefined) {
      } else if(mod[ref] != this.get(attr)) {
        Button.set_attribute(this.get('model'), ref, this.get(attr));
      }
      mod[ref] = this.get(attr);
      vals[this.get('model.id')] = mod;
      this.set('last_values', vals);
    }
  }.observes('model', 'model.id', 'model.hidden', 'model.link_disabled'),
  buttonActions: function() {
    var res = [
      {name: i18n.t('talk', "Add button to the vocalization box"), id: "talk"},
      {name: i18n.t('folder', "Open/Link to another board"), id: "folder"},
      {name: i18n.t('link', "Open a web site in a browser tab"), id: "link"},
      {name: i18n.t('app', "Launch an application"), id: "app"}
    ];
    if(app_state.get('feature_flags.app_connections')) {
      res.push({name: i18n.t('integration', "Activate a connected tool"), id: "integration"});
    }
    return res;
  }.property('app_state.feature_flags.app_connections'),
  book_link_options: function() {
    return [
      {name: i18n.t('large_links', "Large navigation links"), id: 'large'},
      {name: i18n.t('huge_links', "Huge navigation links"), id: 'huge'},
      {name: i18n.t('small_links', "Small navigation links"), id: 'small'}
    ];
  }.property(),
  book_background_options: function() {
    return [
      {name: i18n.t('white_background', "White background"), id: 'white'},
      {name: i18n.t('black_background', "Black background"), id: 'black'}
    ];
  }.property(),
  book_text_positioning_options: function() {
    return [
      {name: i18n.t('text_below', "Show text below images"), id: 'text_below'},
      {name: i18n.t('text_above', "Show text above images"), id: 'text_above'}
    ];
  }.property(),
  image_matches_book: function() {
    return this.get('book_status.image') && this.get('book_status.image') == this.get('model.image.source_url');
  }.property('book_status.image', 'model.image.source_url'),
  image_matches_video_thumbnail: function() {
    return this.get('model.video.thumbnail_url') && this.get('model.video.thumbnail_url') == this.get('model.image.source_url');
  }.property('model.video.thumbnail_url', 'model.image.source_url'),
  non_https: function() {
    return (this.get('model.url') || '').match(/^http:/);
  }.property('model.url'),
  load_book: function() {
    var _this = this;
    var id = _this.get('model.book.id');
    if(id) {
      _this.set('book_status', {loading: true});
      persistence.ajax("/api/v1/search/external_resources?source=tarheel_book&q=" + encodeURIComponent(id), {type: 'GET'}).then(function(list) {
        if(_this.get('model.book.id') == id) {
          var image_page = list.find(function(page) { return !page.small_image; }) || {};
          _this.set('book_status', {
            image: image_page.image,
            content_type: image_page.image_content_type || 'image/jpeg',
            title: list[0].title
          });
        }
      }, function(err) {
        _this.set('book_status', {error: true});
      });
    }
  }.observes('model.book.id'),
  tool_action_types: function() {
    return [
      {name: i18n.t('trigger_webhook', "Trigger an external action"), id: 'webhook'},
      {name: i18n.t('render_page', "Load a tool-rendered page"), id: 'render'}
    ];
  }.property(),
  levelTypes: function() {
    return [
      {name: i18n.t('no_levels', "No Level Overrides"), id: 'none'},
      {name: i18n.t('basic_levels', "Basic Level Overrides"), id: 'basic'},
      {name: i18n.t('advanced_levels', "Custom Level Overrides"), id: 'advanced'}
    ];
  }.property(),
  board_levels: CoughDrop.board_levels,
  basic_level_style: function() {
    return this.get('model.level_style') == 'basic';
  }.property('model.level_style'),
  advanced_level_style: function() {
    return this.get('model.level_style') == 'advanced';
  }.property('model.level_style'),
  tool_types: function() {
    var res = [];
    res.push({name: i18n.t('select_tool', "[Select Tool]"), id: null});
    (this.get('user_integrations') || []).forEach(function(tool) {
      res.push({name: tool.get('name'), id: tool.get('id')});
    });
    return res;
  }.property('user_integrations'),
  update_integration: function() {
    var _this = this;
    if(!this.get('user_integrations.length')) { return; }
    if(this.get('integration_id')) {
      var tool = (_this.get('user_integrations') || []).find(function(t) { return t.get('id') == _this.get('integration_id'); });
      if(tool) {
        var action_type = (!tool.get('has_multiple_actions') && tool.get('render')) ? 'render' : 'webhook';
        var local_url = null;
        if(tool.get('button_webhook_local') && tool.get('button_webhook_url')) {
          local_url = tool.get('button_webhook_url');
        }
        _this.set('model.integration', {
          user_integration_id: tool.id,
          local_url: local_url,
          action_type: action_type
        });
        _this.set('selected_integration', tool);
      }
    } else {
      _this.set('selected_integration', null);
      _this.set('model.integration', null);
    }
  }.observes('integration_id', 'user_integrations'),
  update_integration_id: function() {
    if(!this.get('integration_id') && this.get('model.integration.user_integration_id')) {
      this.set('integration_id', this.get('model.integration.user_integration_id'));
    }
  }.observes('model.integration.user_integration_id'),
  missing_library: function() {
    var res = false;
    if(this.get('image_library') == 'lessonpix_required') {
      res = {lessonpix: true};
    } else if(this.get('image_library') == 'pcs_required') {
      res = {pcs: true};
    }
    return res;
  }.property('image_library'),
  current_library: function() {
    var res = {};
    res[this.get('image_library')] = true;
    return res;
  }.property('image_library'),
  search_prompt: function() {
    return "\"" + this.get('model.label') + "\"" + " or URL or search term";
  }.property('model.label'),
  image_libraries: function() {
    var res = [
      {name: i18n.t('open_symbols', "opensymbols.org (default)"), id: 'opensymbols'}
    ];
    if(this.get('lessonpix_enabled')) {
      res.push({name: i18n.t('lessonpix_images', "LessonPix Images"), id: 'lessonpix'});
    }
    if(app_state.get('feature_flags.premium_symbols')) {
      if(this.get('premium_symbols')) {
        res.push({name: i18n.t('pcs_images', "PCS (BoardMaker) Images"), id: 'pcs'});
      }
     }
    if(window.flickr_key) {
      res.push({name: i18n.t('flickr', "Flickr Creative Commons"), id: 'flickr'});
    }
    if(window.custom_search_key) {
      res.push({name: i18n.t('public_domain', "Public Domain Images"), id: 'public_domain'});
    }
    if(window.pixabay_key) {
      res.push({name: i18n.t('pixabay_photos', "Pixabay Photos"), id: 'pixabay_photos'});
      res.push({name: i18n.t('pixabay_vectors', "Pixabay Vector Images"), id: 'pixabay_vectors'});
    }
    if(window.giphy_key) {
      res.push({name: i18n.t('giphy_asl', "GIPHY ASL Signs"), id: 'giphy_asl'});
    }
    if(!this.get('lessonpix_enabled')) {
      res.push({name: i18n.t('lessonpix_images', "LessonPix Images"), id: 'lessonpix_required'});
    }
    if(app_state.get('feature_flags.premium_symbols')) {
      if(!this.get('premium_symbols')) {
        res.push({name: i18n.t('pcs_images', "PCS (BoardMaker) Images"), id: 'pcs_required'});
      }
    }

//    res.push({name: i18n.t('openclipart', "OpenClipart"), id: 'openclipart'});

    if(res.length == 1) { return []; }
    return res;
  }.property('lessonpix_enabled', 'premium_symbols'),
  load_user_integrations: function() {
    var user_id = this.get('model.integration_user_id') || 'self';
    var _this = this;
    if(this.get('model.integrationOrWebhookAction')) {
      if(!this.get('user_integrations.length')) {
        _this.set('user_integrations', {loading: true});
        Utils.all_pages('integration', {user_id: user_id, for_button: true}, function() {
        }).then(function(res) {
          _this.set('user_integrations', res);
        }, function(err) {
          _this.set('user_integrations', {error: true});
        });
      }
    } else {
      _this.set('user_integrations', []);
    }
  }.observes('model.integrationOrWebhookAction', 'model.integration_user_id'),
  parts_of_speech: function() {
    return CoughDrop.parts_of_speech;
  }.property(),
  licenseOptions: function() {
    return CoughDrop.licenseOptions;
  }.property(),
  board_search_options: function() {
    var res = [];
    if(this.get('board.user_name') != app_state.get('currentUser.user_name')) {
      res.push({name: i18n.t('their_boards', "This User's Boards (includes shared)"), id: 'current_user'});
      res.push({name: i18n.t('public_boards', "Public Boards"), id: 'public'});
      res.push({name: i18n.t('their_starred_boards', "This User's Liked Boards"), id: 'current_user_starred'});
      res.push({name: i18n.t('my_public_boards', "My Public Boards"), id: 'personal_public'});
      res.push({name: i18n.t('my_public_boards', "My Liked Public Boards"), id: 'personal_public_starred'});
      // TODO: add My Private Boards, but warn and have option to auto-share if selected
    } else {
      res.push({name: i18n.t('my_boards', "My Boards (includes shared)"), id: 'personal'});
      res.push({name: i18n.t('public_boards', "Public Boards"), id: 'public'});
      res.push({name: i18n.t('starred_boards', "My Liked Boards"), id: 'personal_starred'});
    }
    return res;
  }.property('board.user_name'),
  webcam_unavailable: function() {
    return !contentGrabbers.pictureGrabber.webcam_available();
  }.property(),
  recorder_unavailable: function() {
    return !contentGrabbers.soundGrabber.recorder_available();
  }.property(),
  notSetPrivateImageLicense: function() {
    if(this.get('image_preview.license')) {
      this.set('image_preview.license.private', this.get('image_preview.license.type') == 'private');
    }
    if(this.get('model.image.license')) {
      this.set('model.image.license.private', this.get('model.image.license.type') == 'private');
    }
  }.observes('image_preview', 'image_preview.license.type', 'model.image.license.type'),
  notSetPrivateSoundLicense: function() {
    if(this.get('sound_preview.license')) {
      this.set('sound_preview.license.private', this.get('sound_preview.license.type') == 'private');
    }
    if(this.get('model.sound.license')) {
      this.set('model.sound.license.private', this.get('model.sound.license.type') == 'private');
    }
  }.observes('sound_preview', 'sound_preview.license.type', 'model.sound.license', 'model.sound.license.type'),
  generateButtonStyle: function() {
    boundClasses.add_rule({
      background_color: this.get('model.background_color'),
      border_color: this.get('model.border_color')
    });
    boundClasses.add_classes(this.get('model'));
  }.observes('model.background_color', 'model.border_color'),
  focus_on_state_change: function() {
    var _this = this;
    runLater(function() {
      var $elem = $(".modal-body:visible .content :input:visible:not(button):not(.skip_select):first");
      $elem.focus().select();
    });
  }.observes('state'),
  re_find: function() {
    if(this.get('linkedBoardName')) {
      this.send('find_board');
    }
  }.observes('board_search_type'),
  state: 'general',
  helpState: function() {
    return this.get('state') == 'help';
  }.property('state'),
  generalState: function() {
    return this.get('state') == 'general';
  }.property('state'),
  pictureState: function() {
    return this.get('state') == 'picture';
  }.property('state'),
  actionState: function() {
    return this.get('state') == 'action';
  }.property('state'),
  soundState: function() {
    return this.get('state') == 'sound';
  }.property('state'),
  languageState: function() {
    return this.get('state') == 'language';
  }.property('state'),
  extrasState: function() {
    return this.get('state') == 'extras';
  }.property('state'),
  modifiers: function() {
    var voc = (this.get('model.vocalization') || "");
    if(!voc || !voc.match(/^(:|\+)/)) {
      if(!voc.match(/\&\&/)) {
        return null;
      }
    }
    var parts = voc.split(/\s*&&\s*/);
    var list = [];
    var any_basic = false;
    var specials = Button.special_actions;
    parts.forEach(function(part) {
      if(specials.indexOf(part) >= 0) {
        var special = "unknown";
        if(part == ':clear') {
          special = i18n.t('clear_utterance', "Clear the current utterance");
        } else if(part == ':home') {
          special = i18n.t('home', "Jump to the current home board");
        } else if(part == ':back') {
          special = i18n.t('back', "Go back one board");
        } else if(part == ':backspace') {
          special = i18n.t('backspace', "Erase the last button from the utterance");
        } else if(part == ':beep') {
          special = i18n.t('beep', "Beep");
        } else if(part == ':speak') {
          special = i18n.t('speak', "Speak the full utterance");
        } else if(part == ':hush') {
          special = i18n.t('stop_speaking', "Stop speaking");
        }
        list.push({modifier: part, special: special});
      } else if(part.match(/^\+/)) {
        list.push({basic: true, modifier: part});
        any_basic = true;
      } else if(part.match(/^\:/)) {
        list.push({modifier: part});
      } else {
        list.push({text: part});
      }
    });
    if(any_basic) {
      emberSet(list, 'any_basic', true);
    } else {
      emberSet(list, 'none_basic', true);
    }
    return list;
  }.property('model.vocalization'),
  ios_search: function() {
    return this.get('app_find_mode') == 'ios' || !this.get('app_find_mode');
  }.property('app_find_mode'),
  android_search: function() {
    return this.get('app_find_mode') == 'android';
  }.property('app_find_mode'),
  web_search: function() {
    return this.get('app_find_mode') == 'web';
  }.property('app_find_mode'),
  track_video: function() {
    if(this.get('model.video.popup') && this.get('model.video.test_url') && !this.get('player')) {
      var _this = this;
      CoughDrop.Videos.track('link_video_preview').then(function(player) {
        _this.set('player', player);
      });
    }
  }.observes('model.video.popup', 'model.video.test_url'),
  video_test_url: function() {
    var host = window.default_host || capabilities.fallback_host;
    if(this.get('model.video.id') && this.get('model.video.type')) {
      return host + "/videos/" + this.get('model.video.type') + "/" + this.get('model.video.id') + "?testing=true&start=" + (this.get('model.video.start') || '') + "&end=" + (this.get('model.video.end') || '');
    } else {
      return null;
    }
  }.property('model.video.id', 'model.video.type', 'model.video.start', 'model.video.end'),
  ios_status_class: function() {
    var res = "glyphicon ";
    if(this.get('model.apps.ios')) {
      res = res + "glyphicon-check ";
    } else {
      res = res + "glyphicon-unchecked ";
    }
    return res;
  }.property('model.apps.ios'),
  android_status_class: function() {
    var res = "glyphicon ";
    if(this.get('model.apps.android')) {
      res = res + "glyphicon-check ";
    } else {
      res = res + "glyphicon-unchecked ";
    }
    return res;
  }.property('model.apps.android'),
  web_status_class: function() {
    var res = "glyphicon ";
    if(this.get('model.apps.web.launch_url')) {
      res = res + "glyphicon-check ";
    } else {
      res = res + "glyphicon-unchecked ";
    }
    return res;
  }.property('model.apps.web.launch_url'),
  fake_button_class: function() {
    var res = "fake_button ";
    if(this.get('model.display_class')) {
      res = res + this.get('model.display_class') + " ";
    }
    return res;
  }.property('model.display_class'),
  webcam_class: function() {
    var res = "button_image ";
    if(this.get('webcam.snapshot')) {
      res = res + "hidden ";
    } else {
      res = res + "shown ";
    }
    return res;
  }.property('webcam.snapshot'),
  show_libraries: function() {
    return true;
//     var previews = this.get('image_search.previews');
//     return (previews && previews.length > 0) || this.get('image_search.previews_loaded') || this.get('image_search.error');
  }.property('image_search.previews', 'image_search.previews_loaded', 'image_search.error'),
  actions: {
    nothing: function() {
      // I had some forms that were being used mainly for layout and I couldn't
      // figure out other than this how to get them to stop submitting when the
      // enter key was hit in some text fields. Weird thing was it wasn't all text
      // fields..
    },
    toggle_color: function(type) {
      var $elem = $("#" + type);

      if(!$elem.hasClass('minicolors-input')) {
        $elem.minicolors();
      }
      if($elem.next().next(".minicolors-panel:visible").length > 0) {
        $elem.minicolors('hide');
      } else {
        $elem.minicolors('show');
      }
    },
    move: function(direction) {
      var row = null, col = null;
      var board = this.get('board');
      var new_button_id = null;
      var old_button_id = this.get('model.id');
      var grid = editManager.get('controller.ordered_buttons') || this.get('board.grid.order') || [];
      grid.forEach(function(list, r) {
        (list || []).forEach(function(button_id, c) {
          button_id = emberGet(button_id, 'id') || button_id;
          if(button_id != null && old_button_id != undefined && button_id.toString() == old_button_id.toString()) {
            row = r;
            col = c;
          }
        })
      })
      if(row !== null && col !== null) {
        if(direction == 'up') {
          new_button_id = (grid[row - 1] || [])[col];
        } else if(direction == 'down') {
          new_button_id = (grid[row + 1] || [])[col];
        } else if(direction == 'right') {
          new_button_id = grid[row][col + 1];
        } else if(direction == 'left') {
          new_button_id = grid[row][col - 1];
        }
      }
      if(new_button_id) {
        new_button_id = emberGet(new_button_id, 'id') || new_button_id;
        modal.close();
        runLater(function() {
          var button = editManager.find_button(new_button_id);
          button.state = event || 'general';
          modal.open('button-settings', {button: button, board: board});
        }, 100);
          
      }
    },
    setState: function(state) {
      this.set('state', state);
    },
    clear_button: function() {
      editManager.clear_button(this.get('model.id'));
      modal.close(true);
    },
    swapButton: function() {
      editManager.prep_for_swap(this.get('model.id'));
      modal.close(true);
    },
    stash_button: function() {
      editManager.stash_button(this.get('model.id'));
      this.set('stashed', true);
    },
    webcamPicture: function() {
      contentGrabbers.pictureGrabber.start_webcam();
    },
    swapStreams: function() {
      contentGrabbers.pictureGrabber.swap_streams();
    },
    webcamToggle: function(takePic) {
      contentGrabbers.pictureGrabber.toggle_webcam(!takePic);
    },
    find_board: function() {
      contentGrabbers.boardGrabber.find_board();
    },
    build_board: function() {
      contentGrabbers.boardGrabber.build_board();
    },
    plus_minus: function(direction, attribute) {
      var value = parseInt(this.get(attribute), 10);
      if(direction == 'minus') {
        value = value - 1;
      } else {
        value = value + 1;
      }
      value = Math.min(Math.max(1, value), 20);
      this.set(attribute, value);
    },
    cancel_build_board: function() {
      contentGrabbers.boardGrabber.cancel_build_board();
    },
    selectFoundBoard: function(board, force) {
      contentGrabbers.boardGrabber.pick_board(board, force);
    },
    copy_found_board: function() {
      contentGrabbers.boardGrabber.copy_found_board();
    },
    create_board: function() {
      contentGrabbers.boardGrabber.create_board({source_id: this.get('model.id')});
    },
    clearImageWork: function() {
      contentGrabbers.pictureGrabber.clear();
    },
    clear_image_preview: function() {
      contentGrabbers.pictureGrabber.clear_image_preview();
    },
    clear_sound_work: function() {
      contentGrabbers.soundGrabber.clear_sound_work();
    },
    clear_sound: function() {
      this.set('model.sound', null);
    },
    pick_preview: function(preview) {
      contentGrabbers.pictureGrabber.pick_preview(preview);
    },
    find_picture: function() {
      var text = this.get('model.image_field');
      if(!text) {
        this.set('model.image_field', this.get('model.label'));
        text = this.get('model.label');
      }
      stashes.persist('last_image_library', this.get('image_library'));
      contentGrabbers.pictureGrabber.find_picture(text, this.get('board.user_name'));
    },
    set_as_button_image: function(url, content_type) {
      var _this = this;
      var preview = {
        url: url,
        content_type: content_type,
        protected: false
      };

      var save = contentGrabbers.pictureGrabber.save_image_preview(preview);

      var id = _this.get('model.id');
      save.then(function(image) {
        image.set('source_url', url);
        var button = editManager.find_button(id);
        if(_this.get('model.id') == id && button) {
          emberSet(button, 'image_id', image.id);
          emberSet(button, 'image', image);
        }
      }, function() {
        alert('nope');
      });
    },
    edit_image_preview: function() {
      contentGrabbers.pictureGrabber.edit_image_preview();
    },
    edit_image: function() {
      contentGrabbers.pictureGrabber.edit_image();
    },
    word_art: function() {
      var text = this.get('model.image_field') || this.get('model.vocalization') || this.get('model.label');
      contentGrabbers.pictureGrabber.word_art(text);
    },
    clear_image: function() {
      contentGrabbers.pictureGrabber.clear_image();
    },
    select_image_preview: function(url) {
      contentGrabbers.pictureGrabber.select_image_preview(url);
    },
    testVocalization: function() {
      var text = this.get('model.vocalization') || this.get('model.label');
      if(this.get('modifiers.length') && this.get('modifier_text')) {
        var b = Button.create({label: this.get('modifier_text')});
        var m = Button.create({label: this.get('modifier')});
        var res = b;
        this.get('modifiers').forEach(function(mod) {
          b.set('in_progress', true);
          res = utterance.modify_button(res, Button.create({label: mod.modifier}));
        })
        utterance.speak_text(res.get('label'));
      } else {
        utterance.speak_text(text);
      }
    },
    record_sound: function() {
      contentGrabbers.soundGrabber.record_sound();
    },
    toggle_recording_sound: function(action) {
      contentGrabbers.soundGrabber.toggle_recording_sound(action);
    },
    select_sound_preview: function() {
      contentGrabbers.soundGrabber.select_sound_preview();
    },
    close: function() {
      if(this.get('model.vocalization')) {
        this.send('clear_sound');
        this.send('clear_sound_work');
        this.set('model.sound_id', null);
      }
      contentGrabbers.save_pending().then(function() {
        modal.close();
      }, function() {
        modal.close();
      });
    },
    find_app: function() {
      contentGrabbers.linkGrabber.find_apps();
    },
    pick_app: function(app) {
      contentGrabbers.linkGrabber.pick_app(app);
    },
    set_app_find_mode: function(mode) {
      contentGrabbers.linkGrabber.set_app_find_mode(mode);
    },
    set_custom: function() {
      contentGrabbers.linkGrabber.set_custom();
    },
    set_time: function(time_attr) {
      if(this.get('player')) {
        var time = Math.round(this.get('player').current_time());
        if(time) {
          this.get('model').set('video.' + time_attr, time);
        }
      }
    },
    clear_times: function() {
      this.get('model').setProperties({
        'video.start': '',
        'video.end': ''
      });
    },
    browse_audio: function() {
      contentGrabbers.soundGrabber.browse_audio();
    },
    audio_selected: function(sound) {
      this.set('model.sound', sound);
      contentGrabbers.soundGrabber.clear_sound_work();
    },
    quick_action: function(action) {
      var _this = this;
      if(action == 'picture') {
        _this.set('state', 'picture');
        runLater(function() {
          _this.send('find_picture');
        }, 200);
      } else if(action == 'label') {
        _this.set('state', 'general');
      } else if(action == 'sound') {
        _this.set('state', 'sound');
      } else if(action == 'folder') {
        _this.set('model.buttonAction', 'folder');
        _this.set('state', 'action');
      } else if(action == 'url') {
        _this.set('model.buttonAction', 'link');
        _this.set('state', 'action');
      } else if(action == 'hide') {
        _this.set('model.hidden', !(this.get('model.hidden')));
        _this.set('paint_hide_reminder', true);
      }
    },
    enable_auto_help: function() {
      var user = app_state.get('currentUser');
      if(user) {
        this.set('auto_help', true);
        user.set('preferences.disable_button_help', false);
        user.save();
      }
    },
    disable_auto_help: function() {
      var user = app_state.get('currentUser');
      if(user) {
        this.set('auto_help', false);
        user.set('preferences.disable_button_help', true);
        user.save();
      }
    }
  }
});
