import Ember from 'ember';
import Component from '@ember/component';
import app_state from '../../utils/app_state';
import i18n from '../../utils/i18n';
import { htmlSafe } from '@ember/string';

export default Component.extend({
  elem_class: function() {
    if(this.get('side_by_side')) {
      return htmlSafe('col-xs-6');
    } else {
      return htmlSafe('col-xs-12');
    }
  }.property('side_by_side'),
  elem_style: function() {
    if(this.get('right_side')) {
      return htmlSafe('border-left: 1px solid #eee; padding-top: 20px; padding-bottom: 20px;');
    } else {
      return htmlSafe('padding-top: 20px; padding-bottom: 20px');
    }
  }.property('right_side'),
  inner_elem_style: function() {
    if(this.get('tall_filter')) {
      return htmlSafe('height: 110px; line-height: 37px; margin-top: -20px;');
    } else {
      return htmlSafe('line-height: 37px; margin-top: -20px;');
    }
  }.property('tall_filter'),
  filter_list: function() {
    var res = [];
    res.push({name: i18n.t('last_2_months', "Last 2 Months"), id: "last_2_months"});
    res.push({name: i18n.t('2_4_months_ago', "2-4 Months Ago"), id: "2_4_months_ago"});
    res.push({name: i18n.t('custom', "Custom Filter"), id: "custom"});
    if(this.get('snapshots')) {
      res.push({name: '----------------', id: '', disabled: true});
      this.get('snapshots').forEach(function(snap) {
        res.push({name: i18n.t('snapshot_dash', "Snapshot - ") + snap.get('name'), id: 'snapshot_' + snap.get('id')});
      });
    }
    return res;
  }.property('snapshots'),
  tall_filter: function() {
    return this.get('usage_stats.custom_filter') || this.get('ref_stats.custom_filter') || this.get('usage_stats.snapshot_id') || this.get('ref_stats.snapshot_id');
  }.property('usage_stats.custom_filter', 'ref_stats.custom_filter', 'usage_stats.snapshot_id', 'ref_stats.snapshot_id'),
  actions: {
    compare_to: function() {
      this.sendAction('compare_to');
    },
    clear_side: function() {
      this.sendAction('clear_side');
    },
    update_filter: function(type) {
      this.sendAction('update_filter', type);
    }
  }
});
