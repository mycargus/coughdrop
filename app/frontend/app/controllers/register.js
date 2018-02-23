import Ember from 'ember';
import Controller from '@ember/controller';
import CoughDrop from '../app';

export default Controller.extend({
  title: "Register",
  registration_types: CoughDrop.registrationTypes,
  triedToSave: false,
  badEmail: function() {
    var email = this.get('model.email');
    return (this.get('triedToSave') && !email);
  }.property('model.email', 'triedToSave'),
  passwordMismatch: function() {
    var present = this.get('model.password');
    var matches = !present || this.get('model.password') == this.get('model.password2');
    return (present && !matches) || (this.get('triedToSave') && !matches);
  }.property('model.password', 'model.password2', 'triedToSave'),
  shortPassword: function() {
    var password = this.get('model.password') || '';
    var password2 = this.get('model.password2');
    return (this.get('triedToSave') || password == password2) && password.length < 6;
  }.property('model.password', 'model.password2', 'triedToSave'),
  noName: function() {
    var name = this.get('model.name');
    var user_name = this.get('model.user_name');
    return this.get('triedToSave') && !name && !user_name;
  }.property('model.name', 'model.user_name', 'triedToSave'),
  noSpacesName: function() {
    return !!(this.get('model.user_name') || '').match(/[\s\.'"]/);
  }.property('model.user_name'),
});
