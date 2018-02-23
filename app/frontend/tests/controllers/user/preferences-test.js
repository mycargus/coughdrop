import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import startApp from '../../helpers/start-app';

describe('UserPreferencesController', 'controller:user-preferences', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import Ember from 'ember';
// import i18n from '../../utils/i18n';
// import app_state from '../../utils/app_state';
// import utterance from '../../utils/utterance';
// import modal from '../../utils/modal';
// 
// export default EmberObjectController.extend({
//   buttonSpacingList: [
//     {name: i18n.t('extra_small', "Extra-Small (5px)"), id: "extra-small"},
//     {name: i18n.t('small', "Small (10px)"), id: "small"},
//     {name: i18n.t('medium', "Medium (15px)"), id: "medium"},
//     {name: i18n.t('large', "Large (25px)"), id: "large"},
//     {name: i18n.t('huge', "Huge (50px)"), id: "huge"}
//   ],
//   buttonBorderList: [
//     {name: i18n.t('none', "None"), id: "none"},
//     {name: i18n.t('small', "Small (1px)"), id: "small"},
//     {name: i18n.t('medium', "Medium (2px)"), id: "medium"},
//     {name: i18n.t('thick', "Thick (5px)"), id: "large"},
//     {name: i18n.t('huge', "Huge (10px)"), id: "huge"}
//   ],
//   buttonTextList: [
//     {name: i18n.t('none', "None"), id: "none"},
//     {name: i18n.t('small', "Small (14px)"), id: "small"},
//     {name: i18n.t('medium', "Medium (18px)"), id: "medium"},
//     {name: i18n.t('large', "Large (22px)"), id: "large"},
//     {name: i18n.t('huge', "Huge (35px)"), id: "large"}
//   ],
//   activationLocationList: [
//     {name: i18n.t('pointer_release', "Where I Release My Pointer"), id: "end"},
//     {name: i18n.t('pointer_start', "Where I First Press"), id: "start"}
//   ],
//   buttonSpaceList: [
//     {name: i18n.t('dont_stretch', "Don't Stretch Buttons"), id: "none"},
//     {name: i18n.t('prefer_tall', "Stretch Buttons, Taller First"), id: "prefer_tall"},
//     {name: i18n.t('prefer_tall', "Stretch Buttons, Wider First"), id: "prefer_wide"},
//   ],
//   buttonBackgroundList: [
//     {name: i18n.t('white', "White"), id: "#fff"},
//     {name: i18n.t('black', "Black"), id: "#000"}
//   ],
//   scanningModeList: [
//     {name: i18n.t('row_based', "Row-Based Scanning"), id: "row"},
//     {name: i18n.t('column_based', "Column-Based Scanning"), id: "column"},
//     {name: i18n.t('region_based', "Region-Based Scanning"), id: "region"}
//   ],
//   scan_pseudo_options: [
//     {name: i18n.t('select', "Select"), id: "select"},
//     {name: i18n.t('next', "Next"), id: "next"}
//   ],
//   title: function() {
//     return "Preferences for " + this.get('user_name');
//   }.property('user_name'),
//   region_scanning: function() {
//     return this.get('preferences.device.scanning_mode') == 'region';
//   }.property('preferences.device.scanning_mode'),
//   select_keycode_string: function() {
//     if(this.get('preferences.device.scanning_select_keycode')) {
//       return (i18n.key_string(this.get('preferences.device.scanning_select_keycode')) || 'unknown') + ' key';
//     } else {
//       return "";
//     }
//   }.property('preferences.device.scanning_select_keycode'),
//   next_keycode_string: function() {
//     if(this.get('preferences.device.scanning_next_keycode')) {
//       return (i18n.key_string(this.get('preferences.device.scanning_next_keycode')) || 'unknown') + ' key';
//     } else {
//       return "";
//     }
//   }.property('preferences.device.scanning_next_keycode'),
//   needs: 'application',
//   actions: {
//     plus_minus: function(direction, attribute) {
//       var default_value = 1.0;
//       var step = 0.1;
//       var max = 10;
//       var min = 0.1;
//       var empty_on_default = false;
//       if(attribute == 'preferences.device.voice.volume') {
//         max = 2.0;
//       } else if(attribute == 'preferences.device.voice.pitch') {
//         max = 2.0;
//       } else if(attribute == 'preferences.activation_cutoff') {
//         min = 0;
//         max = 5000;
//         step = 100;
//         default_value = 0;
//         empty_on_default = true;
//       } else if(attribute == 'preferences.activation_minimum') {
//         min = 0;
//         max = 5000;
//         step = 100;
//         default_value = 0;
//         empty_on_default = true;
//       } else if(attribute == 'preferences.board_jump_delay') {
//         min = 100;
//         max = 5000;
//         step = 100;
//         default_value = 500;
//       } else if(attribute == 'preferences.device.scanning_interval') {
//         min = 0;
//         max = 5000;
//         step = 100;
//         default_value = 1000;
//       } else if(attribute == 'preferences.device.scanning_region_columns' || attribute == 'preferences.device.scanning_region_rows') {
//         min = 1;
//         max = 10;
//         step = 1;
//       }
//       var value = parseFloat(this.get(attribute), 10) || default_value;
//       if(direction == 'minus') {
//         value = value - step;
//       } else {
//         value = value + step;
//       }
//       value = Math.round(Math.min(Math.max(min, value), max) * 100) / 100;
//       if(value == default_value && empty_on_default) {
//         value = "";
//       }
//       this.set(attribute, value);
//     },
//     savePreferences: function() {
//       // TODO: add a "save pending..." status somewhere
//       // TODO: this same code is in utterance.js...
//       var pitch = parseFloat(this.get('preferences.device.voice.pitch'));
//       if(isNaN(pitch)) { pitch = 1.0; }
//       var volume = parseFloat(this.get('preferences.device.voice.volume'));
//       if(isNaN(volume)) { volume = 1.0; }
//       this.set('preferences.device.voice.pitch', pitch);
//       this.set('preferences.device.voice.volume', volume);
// 
//       var user = this.get('model');
//       user.set('preferences.progress.preferences_edited', true);
//       var _this = this;
//       user.save().then(function(user) {
//         if(user.get('id') == app_state.get('currentUser.id')) {
//           app_state.set('currentUser', user);
//         }
//         _this.transitionToRoute('user', user.get('user_name'));
//       });
//     },
//     cancelSave: function() {
//       var user = this.get('model');
//       user.rollback();
//       this.transitionToRoute('user', user.get('user_name'));
//     },
//     test_voice: function() {
//       utterance.test_voice(this.get('preferences.device.voice.voice_uri'), this.get('preferences.device.voice.rate'), this.get('preferences.device.voice.pitch'), this.get('preferences.device.voice.volume'));
//     },
//     delete_logs: function() {
//       modal.open('confirm-delete-logs', {user: this.get('model')});
//     }
//   }
// });