import Ember from 'ember';
import DS from 'ember-data';
import CoughDrop from '../app';
import i18n from '../utils/i18n';

CoughDrop.Gift = DS.Model.extend({
  code: DS.attr('string'),
  duration: DS.attr('string'),
  seconds: DS.attr('number'),
  created: DS.attr('date'),
  licenses: DS.attr('number'),
  active: DS.attr('boolean'),
  purchase: DS.attr('string'),
  organization: DS.attr('string'),
  gift_name: DS.attr('string'),
  email: DS.attr('string'),
  amount: DS.attr('number')
});

export default CoughDrop.Gift;

