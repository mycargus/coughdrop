import Ember from 'ember';
import modal from '../utils/modal';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import Utils from '../utils/misc';
import word_suggestions from '../utils/word_suggestions';

export default modal.ModalController.extend({
  opening: function() {
    var supervisees = [];
    this.set('for_user_id', null);
    this.set('phrase', null);
    this.set('category', null);
    this.set('supervisees', supervisees);
    this.set('custom_phrase', null);
    if(supervisees.length === 0 && !this.get('model.user')) {
      this.set('model.user', app_state.get('currentUser'));
    }
    this.load_recordings();
    this.set('repository',   {
      "id": "boston_childrens",
      "name": "Boston Children's Hospital Message Banking Suggestions",
      "url": "https://www.facebook.com/ACPCHBoston/posts/1253658727989495",
      "description": "This list is not intended as a minimum list of phrases, but rather as a collection of possible phrases others have used that might be beneficial. You should choose the phrases that feel most natural or useful (or use them as inspiration for your own phrases) instead of trying to record them all.",
      "categories": [
        {
          "id": "idioms",
          "name": "Idioms",
          "phrases": [
            {"id": "not_my_cup_of_tea", "text": "It's not my cup of tea"},
            {"id": "just_like_a_dream", "text": "Just like a dream"},
            {"id": "off_the_deep_end", "text": "Off the deep end"},
            {"id": "once_in_a_blue_moon", "text": "Once in a blue moon"},
            {"id": "out_of_the_clear_blue", "text": "Out of the clear blue"},
            {"id": "practice_makes_perfect", "text": "Practice makes perfect"},
            {"id": "way_the_cookie_crumbles", "text": "That's the way the cookie crumbles"},
            {"id": "missed_the_boat", "text": "You missed the boat"}
          ]
        },
        {
          "id": "social_requests",
          "name": "Social Requests",
          "phrases": [
            {"id": "come_talk_with_me", "text": "Come talk with me"},
            {"id": "i_want_a_hug", "text": "I want a hug"},
            {"id": "i_want_a_kiss", "text": "I want a kiss"},
            {"id": "sorry_have_an_appointment", "text": "I'm sorry but I have an appointment now"},
            {"id": "leave_me_alone", "text": "Leave me alone"},
            {"id": "go_with_you", "text": "May I go with you?"},
            {"id": "sit_with_me", "text": "Sit over here with me"},
            {"id": "like_me_to_go_with_you", "text": "Would you like me to go with you?"},
            {"id": "youll_have_to_go", "text": "You'll have to go"}
          ]
        }
      ]
    });
  },
  load_recordings: function(force) {
    if(!this.get('model.recordings') || force) {
      var _this = this;
      Utils.all_pages('sound', {user_id: this.get('model.id')}, function(res) {
      }).then(function(res) {
        _this.set('model.recordings', res);
      }, function(err) {
        modal.error(i18n.t('error_loading_recordings', "There was an unexpected error loading user recordings"));
      });
    } else {
      this.set('recordings', this.get('model.recordings'));
    }
  },
  align_repository: function() {
    if(this.get('repository.id') && this.get('recordings')) {
      var sounds = this.get('recordings') || [];
      var sounds_hash = {};
      sounds.forEach(function(s) {
        (s.get('tags') || []).forEach(function(tag) {
          sounds_hash[tag] = s;
        });
      });
      var rep = this.get('repository');
      // iterate through categories
      (rep.categories || []).forEach(function(cat) {
        Ember.set(cat, 'pending_sound', false);
        // check existing categories for matching sounds
        (cat.phrases || []).forEach(function(phrase) {
          Ember.set(phrase, 'pending_sound', false);
          var tag = rep.id + ":" + cat.id + ":" + phrase.id;
          if(sounds_hash[tag]) {
            Ember.set(phrase, 'sound', sounds_hash[tag]);
          } else if(!Ember.get(phrase, 'sound')) {
            // try to fuzzy-match based on transcription
            var match_distance = phrase.text.length + 10;
            sounds.forEach(function(s) {
              var trans = s.get('transcription') && s.get('transcription').toLowerCase();
              if(trans) {
                if(trans == phrase.text.toLowerCase()) {
                  Ember.set(phrase, 'sound', s);
                  Ember.set(phrase, 'pending_sound', true);
                  Ember.set(cat, 'pending_sound', true);
                  match_distance = 0;
                } else if(match_distance !== 0) {
                  var dist = word_suggestions.edit_distance(trans, phrase.text.toLowerCase());
                  if(dist < match_distance && dist < (Math.max(phrase.text.length, trans.length) * 0.15)) {
                    if((s.get('tags') || []).indexOf("not:" + tag) == -1) {
                      Ember.set(phrase, 'sound', s);
                      Ember.set(phrase, 'pending_sound', true);
                      Ember.set(cat, 'pending_sound', true);
                    }
                  }
                }
              }
            });
          }
        });
        // look for any recordings custom-added to the category
        sounds.forEach(function(s) {
          if(s.get('transcription') && (s.get('tags') || []).indexOf(rep.id + ":" + cat.id) != -1) {
            cat.phrases.pushObject({
              id: s.get('id'),
              text: s.get('transcription'),
              custom: true,
              sound: s
            });
          }
        });
      });
    }
    this.count_totals();
  }.observes('recordings', 'repository.id'),
  count_totals: function() {
    if(this.get('repository.id')) {
      var rep = this.get('repository');
      (rep.categories || []).forEach(function(cat) {
        var cat_sounds = 0;
        // remove any custom-added recordings that the user cleared
        var list = [];
        (cat.phrases || []).forEach(function(phrase) {
          if(!Ember.get(phrase, 'custom') || Ember.get(phrase, 'sound') || Ember.get(phrase, 'pending_sound')) {
            list.push(phrase);
            // also tally while you're iterating
            if(Ember.get(phrase, 'sound') && !Ember.get(phrase, 'pending_sound')) {
              cat_sounds++;
            }
          }
        });
        Ember.set(cat, 'phrases', list);
        Ember.set(cat, 'recordings', cat_sounds);
      });
    }
  },
  needs_user: function() {
    return !this.get('model.user');
  }.property('model.user'),
  update_user: function() {
    if(this.get('for_user_id')) {
      if(this.get('for_user_id') == 'self') {
        this.set('model.user', app_state.get('current_user'));
      } else {
        var u = this.get('supervisees').find(function(u) { return u.id == this.get('for_user_id'); });
        this.set('model.user', u);
      }
    }
  }.property('for_user_id'),
  actions: {
    decide_on_recording: function(decision) {
      var sound = this.get('phrase.sound');
      var _this = this;
      if(sound) {
        var tag = this.get('repository.id') + ":" + this.get('category.id') + ":" + this.get('phrase.id');
        if(this.get('phrase.custom')) {
          tag = this.get('repository.id') + ":" + this.get('category.id');
        }
        if(decision == 'reject') {
          tag = "not:" + tag;
        }
        sound.set('tag', tag);
        sound.save().then(function() {
          _this.set('phrase.pending_sound', false);
          if(decision == 'reject') {
            _this.set('phrase.sound', null);
          }
          _this.count_totals();
        }, function(err) {
          modal.error(i18n.t('error_updating_recording', "There was an unexpected error while updating the recording settings"));
        });
      }
    },
    select_category: function(id) {
      var category = null;
      var next_category = null;
      var prev_category = null;
      (this.get('repository.categories') || []).forEach(function(cat) {
        if(cat.id == id) {
          category = cat;
        } else if(category && !next_category) {
          next_category = cat;
        } else if(!category) {
          prev_category = cat;
        }
      });
      this.set('category', category);
      this.set('next_category', next_category);
      this.set('phrase', null);
      this.set('custom_phrase', null);
      Ember.run.later(function() {
        Ember.$(".modal-content").scrollTop(0);
      });
    },
    select_phrase: function(id) {
      var phrase = null;
      var next_phrase = null;
      var prev_phrase = null;
      (this.get('category.phrases') || []).forEach(function(p) {
        if(id && p.id == id) {
          phrase = p;
        } else if(phrase && !next_phrase) {
          next_phrase = p;
        } else if(!phrase) {
          prev_phrase = p;
        }
      });
      this.set('phrase', phrase);
      this.set('next_phrase', next_phrase);
      Ember.run.later(function() {
        Ember.$(".modal-content").scrollTop(0);
      });
    },
    audio_ready: function(sound) {
      if(this.get('phrase')) {
        this.set('phrase.sound', sound);
        this.send('decide_on_recording', 'accept');
      }
    },
    audio_not_ready: function() {
      if(this.get('phrase')) {
        if(this.get('phrase.sound')) {
          this.send('decide_on_recording', 'reject');
        }
      }
    },
    add_phrase: function(confirm) {
      if(confirm) {
        if(this.get('custom_phrase.text')) {
          this.get('category.phrases').pushObject({
            id: (new Date()).getTime() + ":" + Math.random(),
            text: this.get('custom_phrase.text'),
            custom: true,
            pending_sound: true
          });
          this.set('category.pending_sound', true);
        }
        this.set('custom_phrase', null);
      } else {
        this.set('custom_phrase', {});
        Ember.run.later(function() {
          Ember.$("#custom_phrase_text").focus();
        }, 50);
      }
    },
    confirm_add_phrase: function() {
      this.send('add_phrase', 'confirm');
    },
    cancel_add_phrase: function() {
      this.set('custom_phrase', null);
    }
  }
});
