import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import startApp from '../helpers/start-app';

describe('RegisterController', 'controller:register', function() {
  it("should exist", function() {
    expect(this).not.toEqual(null);
    expect(this).not.toEqual(window);
  });
});
// import Ember from 'ember';
// 
// export default EmberObjectController.extend({
//   title: "Register",
//   triedToSave: false,
//   badEmail: function() {
//     var email = this.get('email');
//     return (this.get('triedToSave') && !email);
//   }.property('email', 'triedToSave'),
//   passwordMismatch: function() {
//     var present = this.get('password');
//     var matches = !present || this.get('password') == this.get('password2');
//     return (present && !matches) || (this.get('triedToSave') && !matches);
//   }.property('password', 'password2', 'triedToSave'),
//   shortPassword: function() {
//     var password = this.get('password') || '';
//     var password2 = this.get('password2');
//     return (this.get('triedToSave') || password == password2) && password.length < 6;
//   }.property('password', 'password2', 'triedToSave'),
//   noName: function() {
//     var name = this.get('name');
//     var user_name = this.get('user_name');
//     return this.get('triedToSave') && !name && !user_name;
//   }.property('name', 'user_name', 'triedToSave')
// });