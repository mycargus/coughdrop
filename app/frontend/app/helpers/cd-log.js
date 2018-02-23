import Ember from 'ember';
import CoughDrop from '../app';

import { helper } from '@ember/component/helper';

export default helper(function(params, hash) {
  if(CoughDrop.log.started) {
    CoughDrop.log.track(params[0]);
  } else {
    console.log(params[0]);
  }
  return "";
});
