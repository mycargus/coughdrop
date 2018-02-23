import Ember from 'ember';

import { helper } from '@ember/component/helper';
export default helper(function(params, hash) {
  return Ember.templateHelpers.path(params[0], hash);
});
