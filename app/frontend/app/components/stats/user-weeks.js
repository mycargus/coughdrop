import Ember from 'ember';
import Component from '@ember/component';
import { later as runLater } from '@ember/runloop';
import $ from 'jquery';
import CoughDrop from '../../app';
import i18n from '../../utils/i18n';

export default Component.extend({
  didInsertElement: function() {
    this.draw();
  },
  draw: function() {
    var $elem = $(this.get('element'));
    $elem.find(".week").tooltip({container: 'body'});
  },
  communicators_with_stats: function() {
    var res = [];
    var _this = this;
    var always_proceed = true;
    if(this.get('weeks') || always_proceed) {
      var user_weeks = {};
      var weeks = this.get('weeks') || {};
      for(var user_id in weeks) {
        user_weeks[user_id] = weeks[user_id];
      }
      weeks = this.get('more_weeks') || {};
      for(var user_id in weeks) {
        user_weeks[user_id] = weeks[user_id];
      }

      var max_count = 1;
      for(var user_id in user_weeks) {
        for(var week_stamp in user_weeks[user_id]) {
          max_count = Math.max(max_count, user_weeks[user_id][week_stamp].count);
        }
      }

      var populated_stamps = this.get('populated_stamps');
      var max_session_count = (this.get('max_session_count') || max_count || 50);
      var session_cutoff = max_session_count * 0.75;
      if(this.get('max_session_count')) {
        max_count = this.get('max_session_count');
      }

      var users = this.get('users') || [];
      if(this.get('more_users')) {
        users = users.concat(this.get('more_users'));
      }
      var totals = {
      };
      users.forEach(function(user) {
        user = $.extend({}, user);
        var weeks = user_weeks[user.id];
        user.week_stats = [];
        populated_stamps.forEach(function(stamp) {
          if(_this.get('user_type') == 'total') {
            var user_level = 0;
            if(weeks && weeks[stamp]) {
              // scale of 0-5, average supervisor activity level
              user_level = weeks[stamp].average_level || 0;
              if(weeks[stamp].count) {
                // # of communicator sessions for the week
                user_level = Math.min(5, Math.round(weeks[stamp].count / (session_cutoff / 5)));
              }
            }
            user.week_stats.push({
              level: user_level
            });
          } else if(_this.get('user_type') == 'communicator') {
            var count = (weeks && weeks[stamp] && weeks[stamp].count) || 0;
            var goals = (weeks && weeks[stamp] && weeks[stamp].goals) || 0;
            var level = Math.round(count / max_count * 10);
            var str = i18n.t('n_sessions', "session", {count: count});
            if(goals > 0) {
              str = str + i18n.t('comma', ", ");
              str = str + i18n.t('n_goals', "goal event", {count: goals});
            }
            user.week_stats.push({
              count: count,
              tooltip: str,
              goals: goals,
              class: 'week level_' + level
            });
          } else {
            var level = weeks && weeks[stamp] && (Math.round(weeks[stamp].average_level * 10) / 10);
            level = level || 0;
            var str = i18n.t('activity_level', "week's activity level: ") + level;
            user.week_stats.push({
              count: level,
              tooltip: str,
              class: 'week level_' + Math.round(level * 2)
            });
          }
        });
        res.push(user);
      });
      if(_this.get('user_type') == 'total' && res.length > 0) {
        var total_users = res.length;
        var u = res[0];
        var new_res = [{
          user_name: 'totals',
          totals: true,
          week_stats: []
        }];
        u.week_stats.forEach(function(week, idx) {
          var stats = {};
          var total_with_any_usage = 0;
          var tally = 0;
          res.forEach(function(user) {
            tally = tally + user.week_stats[idx].level;
            if(user.week_stats[idx].level > 0) {
              total_with_any_usage++;
            }
          });
          var avg = Math.round(tally / total_users * 10) / 10;
          var level = Math.round(avg * 2);
          if(total_with_any_usage > 1) {
            level = Math.max(level, 1);
          }
          // if at least 1/5 users have activity, it will be at least level 2
          if(total_with_any_usage > total_users / 5) {
            level = Math.max(level, 2);
          }
          // if only a few users have activity but it's a noticeable level, set it to at least 2
          if(total_with_any_usage <= 3 && total_users > 5 && tally >= 4.3) {
            level = Math.max(level, 2);
          }
          new_res[0].week_stats.push({
            count: avg,
            tooltip: i18n.t('activity_level', "activity level: ") + avg,
            class: 'week level_' + Math.min(level, 10)
          });
        });
        res = new_res;
      }
    }
    var _this = this;
    runLater(function() {
      _this.draw();
    });
    return res;
  }.property('users', 'weeks', 'more_weeks', 'more_users', 'populated_stamps'),
  labeled_weeks: function() {
    return this.get('populated_stamps').map(function(s) { return window.moment(s * 1000).format('MMM DD, \'YY'); });
  }.property('populated_stamps'),
  populated_stamps: function() {
    var all_weeks = {};
    var weeks = this.get('weeks');
    var more_weeks = this.get('more_weeks');
    for(var user_id in (weeks || {})) {
      all_weeks[user_id] = weeks[user_id];
    }
    for(var user_id in (more_weeks || {})) {
      all_weeks[user_id] = more_weeks[user_id];
    }
    if(weeks) {
      var weeks = all_weeks;
      var all_stamps = [];
      for(var user_id in weeks) {
        for(var week_stamp in weeks[user_id]) {
          if(all_stamps.indexOf(week_stamp) == -1) {
            all_stamps.push(week_stamp);
          }
        }
      }
      all_stamps = all_stamps.sort();
      var populated_stamps = [];
      var cutoff = -3;
      if(this.get('user_type') == 'total') {
        cutoff = -10;
      }
      var three_weeks_ago = window.moment().add(cutoff, 'week').unix();
      if(all_stamps.length === 0 || all_stamps[0] > three_weeks_ago) {
        all_stamps.unshift(three_weeks_ago);
      }
      var ref_stamp = all_stamps[0];
      var now = (new Date()).getTime() / 1000;
      while(ref_stamp < now) {
        if(all_stamps.length > 0) {
          ref_stamp = all_stamps.shift();
        }
        populated_stamps.push(ref_stamp);

        var m = null;
        while(m == null || (ref_stamp < now && ref_stamp < all_stamps[0])) {
          if(m) {
            populated_stamps.push(ref_stamp);
          }
          var m = window.moment(ref_stamp * 1000);
          m.add(1, 'week');
          ref_stamp = m.unix() + 1;
        }
      }
      populated_stamps = populated_stamps.slice(-10);
      return populated_stamps;
    }
    return [];
  }.property('weeks', 'more_weeks', 'user_type'),
  actions: {
    delete_action: function(id) {
      this.sendAction('delete_user', this.get('unit'), this.get('user_type'), id);
    }
  }
});

