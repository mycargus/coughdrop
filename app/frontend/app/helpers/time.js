import Ember from 'ember';

import { helper } from '@ember/component/helper';
export default helper(function(params, hash) {
  return Ember.templateHelpers.time(params[0], params[1]);
});