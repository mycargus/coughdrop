import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import startApp from '../../helpers/start-app';

describe('UserEditController', 'controller:user-edit', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import Ember from 'ember';
// import modal from '../../utils/modal';
// import i18n from '../../utils/i18n';
// 
// export default EmberObjectController.extend({
//   title: function() {
//     return "Edit " + this.get('user_name');
//   }.property('user_name'),
//   actions: {
//     enable_change_password: function() {
//       this.set('change_password', true);
//     },
//     saveProfile: function() {
//       // TODO: add a "save pending..." status somewhere
//       var user = this.get('model');
//       user.set('preferences.progress.profile_edited', true);
//       var _this = this;
//       user.save().then(function() {
//         user.set('password', null);
//         _this.transitionToRoute('user', user.get('user_name'));
//       }, function(err) {
//         if(err.responseJSON && err.responseJSON.errors && err.responseJSON.errors[0] == "incorrect current password") {
//           modal.error(i18n.t('incorrect_password', "Incorrect current password"));
//         } else {
//           modal.error(i18n.t('save_failed', "Save failed."));
//         }
//         
//       });
//     },
//     cancelSave: function() {
//       var user = this.get('model');
//       user.rollback();
//       this.transitionToRoute('user', user.get('user_name'));
//     }
//   }
// });