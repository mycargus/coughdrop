import Ember from 'ember';

import { helper } from '@ember/component/helper';
export default helper(function(params) {
  return Ember.templateHelpers.delimit(params[0], params[1]);
});
