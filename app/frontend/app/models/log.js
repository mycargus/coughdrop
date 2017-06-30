import Ember from 'ember';
import DS from 'ember-data';
import CoughDrop from '../app';

export default DS.Model.extend({
  type: DS.attr('string'),
  events: DS.attr('raw'),
  note: DS.attr('raw'),
  device: DS.attr('raw'),
  author: DS.attr('raw'),
  daily_use: DS.attr('raw'),
  user: DS.attr('raw'),
  imported: DS.attr('boolean'),
  started_at: DS.attr('date'),
  ended_at: DS.attr('date'),
  summary: DS.attr('string'),
  time_id: DS.attr('number'),
  button_count: DS.attr('number'),
  utterance_count: DS.attr('number'),
  utterance_word_count: DS.attr('number'),
  duration: DS.attr('number'),
  user_id: DS.attr('string'),
  timestamp: DS.attr('number'),
  assessment: DS.attr('raw'),
  notify: DS.attr('boolean'),
  next_log_id: DS.attr('string'),
  previous_log_id: DS.attr('string'),
  geo: DS.attr('raw'),
  readable_ip_address: DS.attr('string'),
  ip_cluster_id: DS.attr('string'),
  geo_cluster_id: DS.attr('string'),
  video_id: DS.attr('string'),
  goal_id: DS.attr('string'),
  goal_status: DS.attr('string'),
  goal: DS.attr('raw'),
  video: DS.attr('raw'),
  nonce: DS.attr('string'),
  event_note_count: DS.attr('number'),
  minutes: function() {
    return Math.round((this.get('duration') || 0) / 60);
  }.property('duration'),
  session_type: function() {
    return this.get('type') == 'session';
  }.property('type'),
  note_type: function() {
    return this.get('type') == 'note';
  }.property('type'),
  video_type: function() {
    return this.get('type') == 'note' && this.get('note.video');
  }.property('type', 'note'),
  assessment_type: function() {
    return this.get('type') == 'assessment';
  }.property('type'),
  goal_status_class: function() {
    var status = this.get('goal.status');
    if(status == 1) {
      return 'face sad';
    } else if(status == 2) {
      return 'face neutral';
    } else if(status == 3) {
      return 'face happy';
    } else if(status == 4) {
      return 'face laugh';
    } else {
      return '';
    }
  }.property('goal.status'),
  processed_events: function() {
    var result = [];
    var last_ts = null;
    var max_id = Math.max.apply(null, (this.get('events') || []).mapBy('id').compact()) || 0;
    if(max_id < 0) { max_id = 0; }
    var shown_ids = this.get('toggled_event_ids') || [];
    (this.get('events') || []).forEach(function(event, idx) {
      Ember.set(event, 'id', event['id'] || ++max_id);
      Ember.set(event, event.type + "_type", true);
      if(event.action_type) {
        Ember.set(event, 'type_icon', 'glyphicon-flash');
      } else if(event.utterance_type) {
        Ember.set(event, 'type_icon', 'glyphicon-comment');
      } else {
        Ember.set(event, 'type_icon', 'glyphicon-stop');
      }
      if(event.timestamp && last_ts) {
        Ember.set(event, 'delay', event.timestamp - last_ts);
        Ember.set(event, 'long_delay', event.delay > 60);
      }
      if(event.button_type) {
        Ember.set(event, 'part_of_speech', ((event.parts_of_speech || {}).types || [])[0] || 'unknown');
      }
      Ember.set(event, 'show_notes', event.id && shown_ids.indexOf(event.id) >= 0);
      Ember.set(event, 'processed_summary', event.summary);
      if(event.type == 'utterance' && event.utterance_text) {
        Ember.set(event, 'processed_summary', event.summary + " \"" + event.utterance_text + "\"");
      }

      Ember.set(event, 'note_count', (event.notes || []).length);
      last_ts = event.timestamp;
      Ember.set(event, 'type_class', "glyphicon " + Ember.get(event, 'type_icon'));
      Ember.set(event, 'part_of_speech_class', "part_of_speech_box " + Ember.get(event, 'part_of_speech'));
      result.push(event);
    });
    return result;
  }.property('events', 'toggled_event_ids'),
  processed_tallies: function() {
    var result = [];
    var tallies = [];
    var last_ts = null;
    var running_correct_total = 0;
    var running_total = 0;
    (this.get('assessment.tallies') || []).forEach(function(tally, idx) {
      if(tally.timestamp && last_ts) {
        Ember.set(tally, 'delay', tally.timestamp - last_ts);
      }
      running_total++;
      Ember.set(tally, 'running_total', running_total);
      if(tally.correct) {
        running_correct_total++;
        Ember.set(tally, 'running_correct_total', running_correct_total);
      }
      last_ts = tally.timestamp;
      result.push(tally);
    });
    return result;
  }.property('assessment'),
  daily_use_history: function() {
    var res = [];
    var daily = this.get('daily_use') || [];
    var first = daily[0];
    if(!first) { return null; }
    var date = window.moment(first.date);
    var today = window.moment();
    var finder = function(d) { return d.date == str; };
    while(date <= today) {
      var str = date.format('YYYY-MM-DD');
      var day = daily.find(finder);
      day = day || {date: str, activity: Ember.String.htmlSafe('none')};
      if(day.active === false) {
        day.activity = Ember.String.htmlSafe('light');
      } else if(day.active === true) {
        day.activity = Ember.String.htmlSafe('active');
      }
      res.push(day);
      date = date.add(1, 'day');
    }
    var pct = Math.round(1 / res.length * 1000) / 10;
    res.forEach(function(d) {
      d.display_style = Ember.String.htmlSafe('width: ' + pct + '%;');
    });
    return res;
  }.property('daily_use'),
  toggle_notes: function(event_id) {
    var notes = [];
    var found = false;
    (this.get('toggled_event_ids') || []).forEach(function(id) {
      if(event_id == id) {
        found = true;
      } else {
        notes.push(id);
      }
    });
    if(!found) {
      notes.push(event_id);
    }
    this.set('toggled_event_ids', notes);
  },
  remove_note: function(event_id, note_id) {
    var events = [].concat(this.get('events') || []);
    events.forEach(function(event) {
      if(event.id == event_id) {
        var new_notes = [];
        (event['notes'] || []).forEach(function(note) {
          if(note.id != note_id) {
            new_notes.push(note);
          }
        });
        event.notes = new_notes;
      }
    });
    this.set('events', events);
    this.save().then(null, function() { });
  },
  add_note: function(event_id, text) {
    var events = [].concat(this.get('events') || []);
    events.forEach(function(event) {
      if(event.id == event_id) {
        event['notes'] = event['notes'] || [];
        var max_id = Math.max.apply(null, event['notes'].mapBy('id').compact()) || 0;
        if(max_id < 0) { max_id = 0; }
        event['notes'].push({
          id: ++max_id,
          note: text
        });
      }
    });
    this.set('events', events);
    this.save().then(null, function() { });
  },
  cleanup: function() {
    // TODO: do we need to store the image?
    var events = this.get('events') || [];
    for(var idx = 0; idx < events.length; idx++) {
      delete events[idx]['show_notes'];
      if(events[idx] && events[idx].button && events[idx].button.image && events[idx].button.image.match(/^data/)) {
        events[idx].button.image = null;
      }
    }
    this.set('events', events);
  }
});
