import Ember from 'ember';
import Controller from '@ember/controller';
import persistence from '../../utils/persistence';

export default Controller.extend({
  title: "Reset Password",
  checkPassword: function() {
    var pw = this.get('model.password');
    var pw2 = this.get('model.password2');
    if(!pw) {
      this.set('badPassword', {empty: true});
    } else if(pw.length < 6) {
      this.set('badPassword', {short: true});
    } else if(pw != pw2) {
      this.set('badPassword', {mismatch: true});
    } else {
      console.log('good one!');
      this.set('badPassword', null);
    }
  }.observes('model.password', 'model.password2'),
  cantSubmit: function() {
    this.checkPassword();
    return !!(this.get('badPassword') || this.get('password_reset.succeeded'));
  }.property('badPassword', 'password_reset.succeeded'),
  actions: {
    changePassword: function() {
      var user_name = this.get('model.user_name');
      if(this.get('badPassword')) { return; }
      var token = this.get('model.reset_token');
      var _this = this;
      this.set('password_reset', {pending: true});
      persistence.ajax('/api/v1/users/' + user_name, {
        type: 'POST',
        data: {
          '_method': 'PUT',
          'reset_token': token,
          'user': {
            'password': this.get('model.password')
          }
        }
      }).then(function(data) {
        _this.set('password_reset.pending', false);
        _this.set('password_reset.succeeded', true);
      }, function() {
        _this.set('password_reset.pending', false);
        _this.set('password_reset.failed', true);
      });
    }
  }
});
