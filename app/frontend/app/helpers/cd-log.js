import Ember from 'ember';
import CoughDrop from '../app';

export default Ember.Helper.helper(function(params, hash) {
  if(CoughDrop.log.started) {
    CoughDrop.log.track(params[0]);
  } else {
    console.log(params[0]);
  }
  return "";
});
