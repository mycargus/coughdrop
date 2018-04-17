import Ember from 'ember';
import DS from 'ember-data';
import RSVP from 'rsvp';
import $ from 'jquery';
import CoughDrop from '../app';
import i18n from '../utils/i18n';
import Utils from '../utils/misc';

CoughDrop.Goal = DS.Model.extend({
  didLoad: function() {
    this.check_badges();
  },
  user_id: DS.attr('string'),
  video_id: DS.attr('string'),
  has_video: DS.attr('boolean'),
  primary: DS.attr('boolean'),
  active: DS.attr('boolean'),
  template_id: DS.attr('string'),
  template: DS.attr('boolean'),
  template_header: DS.attr('boolean'),
  global: DS.attr('boolean'),
  summary: DS.attr('string'),
  sequence_summary: DS.attr('string'),
  description: DS.attr('string'),
  sequence_description: DS.attr('string'),
  permissions: DS.attr('raw'),
  currently_running_template: DS.attr('raw'),
  video: DS.attr('raw'),
  user: DS.attr('raw'),
  author: DS.attr('raw'),
  comments: DS.attr('raw'),
  started: DS.attr('date'),
  ended: DS.attr('date'),
  advance: DS.attr('date'),
  expires: DS.attr('date'),
  advancement: DS.attr('string'),
  duration: DS.attr('number'),
  stats: DS.attr('raw'),
  related: DS.attr('raw'),
  sequence: DS.attr('boolean'),
  date_based: DS.attr('boolean'),
  next_template_id: DS.attr('string'),
  template_header_id: DS.attr('string'),
  template_stats: DS.attr('raw'),
  badge_name: DS.attr('string'),
  badge_image_url: DS.attr('string'),
  badges: DS.attr('raw'),
  assessment_badge: DS.attr('raw'),
  goal_advances_at: DS.attr('string'),
  goal_duration_unit: DS.attr('string'),
  goal_duration_number: DS.attr('string'),
  best_time_level: function() {
    var stats = this.get('stats') || {};
    if(stats && stats.monthly && stats.monthly.totals && stats.monthly.totals.sessions > 0) {
      var levels = {};
      var suggested_level = null;
      ['daily', 'weekly', 'monthly'].forEach(function(level) {
        levels[level] = [];
        var hash = stats[level] || {};
        for(var idx in hash) {
          if(idx != 'totals') {
            levels[level].push(idx);
          }
        }
        var last_value = levels[level].sort().reverse()[0];
        // if there's no data, just do daily or something
        // preference for the lowest level
        if(level == 'daily') {
          // if nothing's happened in the last 2 weeks, don't use daily
          // if weekly has the same sessions as daily, use daily
          var two_weeks_ago = window.moment().add(-2, 'weeks').toISOString().substring(0, 10);
          if(last_value > two_weeks_ago) {
            if(stats.weekly && stats.weekly.totals && stats.daily && stats.daily.totals && stats.weekly.totals.sessions == stats.daily.totals.sessions) {
              suggested_level = 'daily';
            }
          }
        } else if(level == 'weekly') {
          // if nothing's happened in the last 12 weeks, don't use weekly
          // if monthly has the same sessions as weekly, use weekly unless already using daily
          var twelve_weeks_ago = window.moment().add(-12, 'weeks').format('GGGG-WW');
          if(last_value > twelve_weeks_ago) {
            if(stats.monthly && stats.monthly.totals && stats.weekly && stats.weekly.totals && stats.monthly.totals.sessions == stats.weekly.totals.sessions) {
              suggested_level = suggested_level || 'weekly';
            }
          }
        } else if(level == 'monthly') {
          suggested_level = suggested_level || 'monthly';
          // otherwise use monthly
        }

      });
      return suggested_level;
    } else {
      return 'none';
    }
  }.property('stats'),
  time_units: function() {
    var level = this.get('best_time_level');
    var stats = this.get('stats');
    var units = [];
    if(level == 'daily') {
      var days = [];
      var day = window.moment();
      for(var idx = 0; idx < 14; idx++) {
        var key = day.toISOString().substring(0, 10);
        days.push({
          key: key,
          label: day.toISOString().substring(0, 10),
          sessions: ((stats.daily[key] || {}).sessions || 0),
          max_statuses: Utils.max_appearance((stats.daily[key] || {}).statuses || [])
        });
        day = day.add(-1, 'days');
      }
      units = days;
    } else if(level == 'weekly') {
      var weeks = [];
      var week = window.moment();
      for(var idx = 0; idx < 12; idx++) {
        var key = week.clone().weekday(1).format('GGGG-WW');
        weeks.push({
          key: key,
          label: week.clone().weekday(0).toISOString().substring(0, 10),
          sessions: ((stats.weekly[key] || {}).sessions || 0),
          max_statuses: Utils.max_appearance((stats.weekly[key] || {}).statuses || [])
        });
        week = week.add(-1, 'weeks');
      }
      units = weeks;
    } else if(level == 'monthly') {
      var months = [];
      var month_keys = [];
      var monthly = this.get('stats').monthly || {};
      for(var idx in monthly) {
        if(idx != 'totals') {
          month_keys.push(idx);
        }
      }
      var last_month = month_keys.sort().reverse()[0];
      var first_month = month_keys.sort()[0];
      var date = window.moment(last_month, 'YYYY-MM');
      for(var idx = 0; idx < 36; idx++) {
        var key = date.format('YYYY-MM');
        months.push({
          key: key,
          label: date.toISOString().substring(0, 10),
          sessions: ((stats.monthly[key] || {}).sessions || 0),
          max_statuses: Utils.max_appearance((stats.monthly[key] || {}).statuses || [])
        });
        date = date.add(-1, 'month');
      }
      units = months;
    }
    var reversed_units = [];
    var found_session = false;
    units.reverse().forEach(function(unit, idx) {
      if(found_session || unit.sessions > 0 || idx > (units.length - 5)) {
        found_session = true;
        reversed_units.push(unit);
      }
    });
    var max = Math.max.apply(null, units.mapBy('max_statuses'));
    reversed_units.max = max;
    return reversed_units;
  }.property('stats', 'best_time_level'),
  unit_description: function() {
    var level = this.get('best_time_level');
    if(level == 'daily') {
      return i18n.t('day', "Day");
    } else if(level == 'weekly') {
      return i18n.t('week', "Week");
    } else if(level == 'monthly') {
      return i18n.t('month', "Month");
    } else {
      return i18n.t('no_unit', "No Data");
    }
  }.property('stats', 'best_time_level'),
  time_unit_measurements: function() {
    return this.get('stats')[this.get('best_time_level')] || {};
  }.property('stats', 'best_time_level'),
  any_statuses: function() {
    var any_found = false;
    (this.get('time_unit_status_rows') || []).forEach(function(row) {
      (row.time_blocks || []).forEach(function(block) {
        if(block && block.score > 0) { any_found = true; }
      });
    });
    return any_found;
  }.property('time_unit_status_rows'),
  time_unit_status_rows: function() {
    if(this.get('best_time_level') == 'none') { return []; }
    var units = this.get('time_units');
    var rows = [{
      status_class: 'face', tooltip: i18n.t('we_did_awesome', "We did awesome! (4)"), time_blocks: []
    }, {
      status_class: 'face happy', tooltip: i18n.t('we_did_good', "We did good! (3)"), time_blocks: []
    }, {
      status_class: 'face neutral', tooltip: i18n.t('we_barely_did_id', "We barely did it (2)"), time_blocks: []
    }, {
      status_class: 'face sad', tooltip: i18n.t('we_didnt_do_it', "We didn't do it (1)"), time_blocks: []
    }];
    for(var idx = 0; idx < 14 && idx < units.length; idx++) {
      var unit = units[idx];
      var unit_stats = (this.get('stats')[this.get('best_time_level')] || {})[unit.key] || {};
      var statuses = unit_stats.statuses || [];
      var score = statuses.filter(function(s) { return s == 4; }).length;
      var level = Math.ceil(score / units.max * 10);
      rows[0].time_blocks.push({
        score: score,
        tooltip: score ? (i18n.t('status_sessions', 'status', {count: score}) + ', ' + unit.label) : "",
        style_class: 'time_block level_' + level
      });
      score = statuses.filter(function(s) { return s == 3; }).length;
      level = Math.ceil(score / units.max * 10);
      rows[1].time_blocks.push({
        score: score,
        tooltip: score ? (i18n.t('status_sessions', 'status', {count: score}) + ', ' + unit.label) : "",
        style_class: 'time_block level_' + level
      });
      score = statuses.filter(function(s) { return s == 2; }).length;
      level = Math.ceil(score / units.max * 10);
      rows[2].time_blocks.push({
        score: score,
        tooltip: score ? (i18n.t('status_sessions', 'status', {count: score}) + ', ' + unit.label) : "",
        style_class: 'time_block level_' + level
      });
      score = statuses.filter(function(s) { return s == 1; }).length;
      level = Math.ceil(score / units.max * 10);
      rows[3].time_blocks.push({
        score: score,
        tooltip: score ? (i18n.t('status_sessions', 'status', {count: score}) + ', ' + unit.label) : "",
        style_class: 'time_block level_' + level
      });
    }
    return rows;
  }.property('stats', 'best_time_level'),
  high_level_summary: function() {
    var res = this.get('sequence') ? this.get('sequence_summary') : null;
    res = res || this.get('summary');
    return res;
  }.property('sequence', 'summary', 'sequence_summary'),
  high_level_description: function() {
    var res = this.get('sequence') ? this.get('sequence_description') : null;
    res = res || this.get('description');
    return res;
  }.property('sequence', 'description', 'sequence_description'),
  advance_type: function() {
    if(this.get('advance')) {
      return 'date';
    } else if(this.get('duration')) {
      return 'duration';
    } else {
      return 'none';
    }
  }.property('advance', 'duration'),
  date_advance: function() {
    return this.get('advance_type') == 'date';
  }.property('advance_type'),
  duration_advance: function() {
    return this.get('advance_type') == 'duration';
  }.property('advance_type'),
  any_advance: function() {
    return this.get('advance_type') && this.get('advance_type') != 'none';
  }.property('advance_type'),
  update_advancement: function() {
    if(this.get('advance_type') == 'date') {
      if(this.get('goal_advances_at')) {
        this.set('advancement', 'date:' + this.get('goal_advances_at'));
      }
    } else if(this.get('advance_type') == 'duration') {
      if(this.get('goal_duration_number') && this.get('goal_duration_unit')) {
        this.set('advancement', 'duration:' + this.get('goal_duration_number') + ':' + this.get('goal_duration_unit'));
      }
    } else {
      this.set('advancement', 'none');
    }
  },
  generate_next_template_if_new: function() {
    if(this.get('new_next_template_id')) {
      var next_template = CoughDrop.store.createRecord('goal');
      next_template.set('template_header_id', this.get('related.header.id'));
      next_template.set('template', true);
      next_template.set('summary', this.get('new_next_template_summary'));
      return next_template.save();
    } else {
      return RSVP.resolve(null);
    }
  },
  new_next_template_id: function() {
    return this.get('next_template_id') == 'new';
  }.property('next_template_id'),
  current_template: function() {
    if(this.get('currently_running_template')) {
      return CoughDrop.store.createRecord('goal', this.get('currently_running_template'));
    } else {
      return this;
    }
  }.property('currently_running_template'),
  remove_badge: function(badge) {
    var badges = (this.get('badges') || []).filter(function(b) { return b != badge; });
    this.set('badges', badges);
  },
  add_badge_level: function() {
    this.set('badges', this.get('badges') || []);
    var badges = this.get('badges') || [];
    var badge = {};
    if(badges.length > 0) {
      badge = $.extend({}, badges[badges.length - 1]);
    }
    badge.level = null;
    badge.image_url = badge.image_url || "https://coughdrop-usercontent.s3.amazonaws.com/images/6/8/8/5/1_6885_5781b0671b2b65ad0b53f2fe-980af0f90c67ef293e98f871270e4bc0096493b2863245a3cff541792acf01050e534135fb96262c22d691132e2721b37b047a02ccaf6931549278719ec8fa08.png";
    badge.id = Math.random();
    this.get('badges').pushObject(badge);
  },
  check_badges: function() {
    var badges = this.get('badges') || [];
    this.set('badges_enabled', !!(badges.length > 0 && badges[badges.length - 1].level > 0));
  }.observes('badges'),
  set_zero_badge: function(obj, changed) {
    if(changed == 'auto_assessment' && this.get('auto_assessment') === false) {
      this.set('assessment_badge', null);
    }
    if(this.get('auto_assessment') || this.get('assessment_badge')) {
      this.set('auto_assessment', true);
      if(!this.get('assessment_badge')) {
        this.set('assessment_badge', {assessment: true});
      }
    } else {
      this.set('auto_assessment', false);
      this.set('assessment_badge', null);
    }
  }.observes('auto_assessment', 'assessment_badge')
});

export default CoughDrop.Goal;
