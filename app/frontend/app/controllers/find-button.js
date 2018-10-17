import Ember from 'ember';
import { later as runLater } from '@ember/runloop';
import RSVP from 'rsvp';
import $ from 'jquery';
import modal from '../utils/modal';
import persistence from '../utils/persistence';
import i18n from '../utils/i18n';
import app_state from '../utils/app_state';
import editManager from '../utils/edit_manager';


export default modal.ModalController.extend({
  opening: function() {
    var _this = this;
    _this.set('searchString', '');
    if(_this.get('model.board')) {
      _this.get('model.board').load_button_set().then(function(bs) {
        _this.set('button_set', bs);
      }, function() {
        _this.set('button_set', null);
      });
    }
    runLater(function() {
      $("#button_search_string").focus();
    }, 100);
  },
  search: function() {
    this.set('results', null);
    var board = modal.settings_for['find-button'].board;
    if(this.get('searchString')) {
      var _this = this;
      _this.set('loading', true);
      _this.set('error', null);
      // TODO: only show other boards if in speak mode!
      var include_other_boards = this.get('model.include_other_boards');
      if(board.get('button_set')) {
        var user = app_state.get('currentUser');
        var include_home = app_state.get('speak_mode');
        var search = null;
        if(app_state.get('feature_flags.find_multiple_buttons')) {
          search = board.get('button_set').find_sequence(this.get('searchString'), board.get('id'), user, include_home);
        } else {
          search = board.get('button_set').find_buttons(this.get('searchString'), board.get('id'), user, include_home);
        }
        search.then(function(results) {
          console.log("results!", results);
          if(persistence.get('online')) {
            _this.set('results', results);
            _this.set('loading', false);
          } else {
            var new_results = [];
            var promises = [];
            results.forEach(function(b) {
              var images = [b.image];
              if(b.sequence) {
                images = b.steps.map(function(s) { return s.button.image; });
              }
              var missing_image = images.find(function(i) { return !i || i.match(/^http/); });
              if(!missing_image) {
                new_results.push(b);
              } else {
              // This is a repeat of what already happens in buttonset.js
              // calling find_url in buttonset.js
              //   if(b.sequence) {
              //     b.steps.forEach(function(s) {
              //       promises.push(persistence.find_url(s.button.image, 'image').then(function(data_uri) {
              //         emberSet(b.button, 'image', data_uri);
              //       }));
              //       new_results.push(b);
              //     })
              //   } else {
              //     promises.push(persistence.find_url(b.image, 'image').then(function(data_uri) {
              //       b.image = data_uri;
              //       new_results.push(b);
              //     }));
              //   }
              }
            });
            RSVP.all_wait(promises).then(null, function() { return RSVP.resolve(); }).then(function() {
              _this.set('results', new_results);
              _this.set('loading', false);
            });
          }
          _this.set('results', results);
          _this.set('loading', false);
        }, function(err) {
          _this.set('loading', false);
          _this.set('error', err.error);
        });
      } else {
        _this.set('loading', false);
        _this.set('error', i18n.t('button_set_not_found', "Button set not downloaded, please try syncing or going online and reopening this board"));
      }
    }
  }.observes('searchString', 'button_set'),
  actions: {
    pick_result: function(result) {
      if(result.board_id == editManager.controller.get('model.id')) {
        var $button = $(".button[data-id='" + result.id + "']");
        var _this = this;
        modal.highlight($button).then(function() {
          var button = editManager.find_button(result.id);
          var board = editManager.controller.get('model');
          app_state.controller.activateButton(button, {board: board});
        }, function() { });
      } else {
        var buttons = result.pre_buttons || [];
        if(result.pre_action == 'home') {
          buttons.unshift('home');
        }
        if(result.sequence) {
          result.steps.forEach(function(step) {
            if(step.sequence.pre == 'home') {
              buttons.push({pre: 'home'});
            }
            step.sequence.buttons.forEach(function(btn) {
              buttons.push(btn);
            });
            buttons.push(step.button);
          });
        } else {
          buttons.push(result);
        }
        app_state.controller.set('button_highlights', buttons);
        app_state.controller.send('highlight_button');
      }
    }
  }
});
