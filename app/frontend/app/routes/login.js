import Ember from 'ember';
import Route from '@ember/routing/route';
import session from '../utils/session';

// TODO: get fresh token on error
export default Route.extend({
  title: "Login",
  setupController: function() {
    if(session.get('isAuthenticated')) {
      debugger
    }
  }
});
