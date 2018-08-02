import Ember from 'ember';
import DS from 'ember-data';
import CoughDrop from '../app';
import i18n from '../utils/i18n';

CoughDrop.Gift = DS.Model.extend({
  didLoad: function() {
    this.update_gift_types();
  },
  code: DS.attr('string'),
  duration: DS.attr('string'),
  seconds: DS.attr('number'),
  created: DS.attr('date'),
  licenses: DS.attr('number'),
  gift_type: DS.attr('string'),
  total_codes: DS.attr('number'),
  redeemed_codes: DS.attr('number'),
  activated_discounts: DS.attr('number'),
  limit: DS.attr('number'),
  expires: DS.attr('date'),
  org_connected: DS.attr('boolean'),
  codes: DS.attr('raw'),
  active: DS.attr('boolean'),
  purchase: DS.attr('string'),
  organization: DS.attr('string'),
  gift_name: DS.attr('string'),
  email: DS.attr('string'),
  memo: DS.attr('string'),
  amount: DS.attr('number'),
  discount: DS.attr('number'),
  discount_hundred: function() {
    return (this.get('discount') || 1.0) * 100;
  }.property('discount'),
  update_gift_types: function() {
    var res = {};
    res[this.get('gift_type') || 'user_gift'] = true;
    this.set('gift_types', res);
  }.observes('gift_type')
});

export default CoughDrop.Gift;

