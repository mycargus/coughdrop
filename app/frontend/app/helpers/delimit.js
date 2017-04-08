import Ember from 'ember';

export default Ember.Helper.helper(function(params) {
  return Ember.templateHelpers.delimit(params[0], params[1]);
});
