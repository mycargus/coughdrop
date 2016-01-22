import Ember from 'ember';
import DS from 'ember-data';
import Resolver from 'ember/resolver';
import loadInitializers from 'ember/load-initializers';
import config from './config/environment';
import capabilities from './utils/capabilities';
import i18n from './utils/i18n';
import persistence from './utils/persistence';
import coughDropExtras from './utils/extras';
import misc from './utils/misc';

Ember.MODEL_FACTORY_INJECTIONS = true;

Ember.onerror = function(err) {
  if(err.stack) {
    console.error(err.stack);
  } else {
    if(err.fakeXHR && err.fakeXHR.status == 400) {
      // should already be logged via "ember ajax error"
    } else if(err.status == 400) {
      // should already be logged via "ember ajax error"
    } else {
      console.error(JSON.stringify(err));
    }
  }
};

// TODO: nice for catching unexpected errors, but it seems like
// it also triggers anytime a reject isn't caught.
// Ember.RSVP.on('error', function(err) {
//   Ember.Logger.assert(false, err);
//   debugger
// });

var customEvents = {
    'buttonselect': 'buttonSelect',
    'buttonpaint': 'buttonPaint',
    'actionselect': 'actionSelect',
    'symbolselect': 'symbolSelect',
    'rearrange': 'rearrange',
    'clear': 'clear',
    'stash': 'stash',
    'select': 'select'
};

var CoughDrop = Ember.Application.extend({
  modulePrefix: config.modulePrefix,
  podModulePrefix: config.podModulePrefix,
  Resolver: Resolver,
  customEvents: customEvents,
  ready: function() {
    // remove the splash screen if showing
    if(capabilities.installed_app || (navigator && navigator.splashscreen && navigator.splashscreen.hide)) {
      var checkForFooter = function() {
        if(Ember.$("footer").length > 0) {
          if(navigator && navigator.splashscreen && navigator.splashscreen.hide) {
            Ember.run.later(navigator.splashscreen.hide, 500);
          } else {
            console.log("splash screen expected but not found");
          }
        } else {
          Ember.run.later(checkForFooter, 200);
        }
      };
      Ember.run.later(checkForFooter, 200);
    }
  }
});


loadInitializers(CoughDrop, config.modulePrefix);

DS.Model.reopen({
  reload: function(allow_local) {
    if(allow_local !== false) {
      persistence.force_reload = this.get('id');
    }
    return this._super();
  },
  save: function() {
    // TODO: this causes a difficult constraint, because you need to use the result of the
    // promise instead of the original record you were saving in any results, just in case
    // the record object changed. It's not ideal, but we have to do something because DS gets
    // mad now if the server returns a different id, and we use a temporary id when persisted
    // locally.
    if(this.id && this.id.match(/^tmp[_\/]/) && persistence.get('online')) {
      var tmp_id = this.id;
      var tmp_key = this.get('key');
      var type = this._internalModel.modelName;
      var attrs = this._internalModel._attributes;
      var rec = this.store.createRecord(type, attrs);
      rec.tmp_key = tmp_key;
      return rec.save().then(function(result) {
        return persistence.remove(type, {}, tmp_id).then(function() {
          return Ember.RSVP.resolve(result);
        }, function() {
          return Ember.RSVP.reject({error: "failed to remove temporary record"});
        });
      });
    }
    return this._super();
  }
});

Ember.Route.reopen({
  update_title_if_present: function() {
    var controller = this.controllerFor(this.routeName);
    var title = this.get('title') || (controller && controller.get('title'));
    if(title) {
      CoughDrop.controller.updateTitle(title.toString());
    }
  },
  activate: function() {
    this.update_title_if_present();
    var controller = this.controllerFor(this.routeName);
    if(controller) {
      controller.addObserver('title', this, function() {
        this.update_title_if_present();
      });
    }
    this._super();
  }
});

CoughDrop.licenseOptions = [
  {name: i18n.t('private_license', "Private (no reuse allowed)"), id: 'private'},
  {name: i18n.t('cc_by_license', "CC By (attribution only)"), id: 'CC By', url: 'http://creativecommons.org/licenses/by/4.0/'},
  {name: i18n.t('cc_by_sa_license', "CC By-SA (attribution + share-alike)"), id: 'CC By-SA', url: 'http://creativecommons.org/licenses/by-sa/4.0/'},
  {name: i18n.t('public_domain_license', "Public Domain"), id: 'public domain', url: 'http://creativecommons.org/publicdomain/zero/1.0/'}
];
CoughDrop.registrationTypes = [
  {name: i18n.t('pick_type', "[ this login is for ]"), id: ''},
  {name: i18n.t('registration_type_communicator', "A communicator"), id: 'communicator'},
  {name: i18n.t('registration_type_slp', "A therapist"), id: 'therapist'},
  {name: i18n.t('registration_type_parent', "A parent"), id: 'parent'},
  {name: i18n.t('registration_type_eval', "An evaluation/assessment device"), id: 'eval'},
  {name: i18n.t('registration_type_other', "An aide, caregiver or other supporter"), id: 'other'}
];
CoughDrop.parts_of_speech = [
  {name: i18n.t('unspecified', "Unspecified"), id: ''},
  {name: i18n.t('noun', "Noun (dog, Dad)"), id: 'noun'},
  {name: i18n.t('verb', "Verb (jump, fly)"), id: 'verb'},
  {name: i18n.t('adjective', "Adjective (silly, red)"), id: 'adjective'},
  {name: i18n.t('pronoun', "Pronoun (he, they)"), id: 'pronoun'},
  {name: i18n.t('adverb', "Adverb (kindly, often)"), id: 'adverb'},
  {name: i18n.t('question', "Question (why, when)"), id: 'question'},
  {name: i18n.t('conjunction', "Conjunction (and, or)"), id: 'conjunction'},
  {name: i18n.t('negation', "Negation (not, never)"), id: 'negation'},
  {name: i18n.t('preposition', "Preposition (behind, with)"), id: 'preposition'},
  {name: i18n.t('article', "Article (a, an)"), id: 'article'},
  {name: i18n.t('determiner', "Determiner (that, his)"), id: 'determiner'},
  {name: i18n.t('other', "Other word type"), id: 'other'},
  {name: i18n.t('custom_1', "Custom Word Type 1"), id: 'custom_1'},
  {name: i18n.t('custom_2', "Custom Word Type 2"), id: 'custom_2'},
  {name: i18n.t('custom_3', "Custom Word Type 3"), id: 'custom_3'}
];
// derived from http://praacticalaac.org/strategy/communication-boards-colorful-considerations/
// and http://talksense.weebly.com/cbb-8-colour.html
CoughDrop.keyed_colors = [
  {border: "#ccc", fill: "#fff", color: i18n.t('white', "White"), types: ['conjunction']},
  {fill: "#ffa", color: i18n.t('yellow', "Yellow"), hint: i18n.t('people', "people"), types: ['pronoun']},
  {fill: "#cfa", color: i18n.t('green', "Green"), hint: i18n.t('actions', "actions"), types: ['verb']},
  {fill: "#fca", color: i18n.t('orange', "Orange"), hint: i18n.t('nouns', "nouns"), types: ['noun', 'nominative']},
  {fill: "#acf", color: i18n.t('blue', "Blue"), hint: i18n.t('describing_words', "describing words"), types: ['adjective']},
  {fill: "#caf", color: i18n.t('purple', "Purple"), hint: i18n.t('questions', "questions"), types: ['question']},
  {fill: "#faa", color: i18n.t('red', "Red"), hint: i18n.t('negations', "negations"), types: ['negation', 'expletive', 'interjection']},
  {fill: "#fac", color: i18n.t('pink', "Pink"), hint: i18n.t('social_words', "social words"), types: ['preposition']},
  {fill: "#ca8", color: i18n.t('brown', "Brown"), hint: i18n.t('adverbs', "adverbs"), types: ['adverb']},
  {fill: "#ccc", color: i18n.t('gray', "Gray"), hint: i18n.t('determiners', "determiners"), types: ['article', 'determiner']}
];

CoughDrop.licenseOptions.license_url = function(id) {
  for(var idx = 0; idx < CoughDrop.licenseOptions.length; idx++) {
    if(CoughDrop.licenseOptions[idx].id == id) {
      return CoughDrop.licenseOptions[idx].url;
    }
  }
  return "";
};

CoughDrop.iconUrls = [
    
    {alt: 'house', url: 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/house.svg'},
    {alt: 'food', url: 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/food.svg'},
    {alt: 'verbs', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/verbs.png'},
    {alt: 'describe', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/to%20explain.png'},
    {alt: 'you', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/you.png'},
    {alt: 'questions', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/ask_2.png'},
    {alt: 'people', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/group%20of%20people_2.png'},
    {alt: 'time', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/clock-watch_6.png'},
    {alt: 'city', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/place.png'},
    {alt: 'world', url: 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/world.svg'},
    {alt: 'clothing', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/clothes.png'},
    {alt: 'cheeseburger', url: 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/cheese%20burger.svg'},
    {alt: 'school', url: 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/school%20bag.svg'},
    {alt: 'fish', url: 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/fish.svg'},
    {alt: 'party', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/party_3.png'},
    {alt: 'shoe', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/shoes_8.png'},
    {alt: 'boy', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/boy_1.png'},
    {alt: 'girl', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/girl_1.png'},
    {alt: 'toilet', url: 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/toilet.svg'},
    {alt: 'car', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/car.png'},
    {alt: 'sun', url: 'https://s3.amazonaws.com/opensymbols/libraries/mulberry/sun.svg'},
    {alt: 'snowman', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/snowman.png'},
    {alt: 'bed', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/bed.png'},
    {alt: 'computer', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/computer_2.png'},
    {alt: 'phone', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/mobile%20phone.png'},
    {alt: 'board', url: 'https://s3.amazonaws.com/opensymbols/libraries/arasaac/board_3.png'}
];

CoughDrop.YT = {
  track: function(player_id, callback) {
    return new Ember.RSVP.Promise(function(resolve, reject) {
      if(!CoughDrop.YT.ready) {
        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        var firstScriptTag = document.getElementsByTagName('script')[0];
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);    
        window.onYouTubeIframeAPIReady = function() {
          CoughDrop.YT.ready = true;
          CoughDrop.YT.track(player_id, callback).then(function(player) {
            resolve(player);
          }, function() { reject('no_player'); });
        };
      } else {
        setTimeout(function() {
          var player = Ember.Object.extend({
            current_time: function() {
              var p = this.get('_player');
              return p && p.getCurrentTime && p.getCurrentTime();
            },
            cleanup: function() {
              this.set('disabled', true);
            },
            pause: function() {
              var p = this.get('_player');
              if(p && p.pauseVideo) {
                p.pauseVideo();
              }
            },
            play: function() {
              var p = this.get('_player');
              if(p && p.playVideo) {
                p.playVideo();
              }
            }
          }).create();
          player.set('_player', new window.YT.Player(player_id, {
            events: {
              'onStateChange': function(event) {
                if(callback) {
                  if(event.data == window.YT.PlayerState.ENDED) {
                    callback('end');
                    player.set('paused', false);
                  } else if(event.data == window.YT.PlayerState.PAUSED) {
                    callback('pause');
                    player.set('paused', true);
                  } else if(event.data == window.YT.PlayerState.CUED) {
                    callback('pause');
                    player.set('paused', true);
                  } else if(event.data == window.YT.PlayerState.PLAYING) {
                    callback('play');
                    player.set('paused', false);
                  }
                }
              }
            }
          }));
          CoughDrop.YT.players = CoughDrop.YT.players || [];
          CoughDrop.YT.players.push(player);
          resolve(player);
        }, 200);
      }
    });
  },
  poll: function() {
    (CoughDrop.YT.players || []).forEach(function(player) {
      if(!player.get('disabled')) {
        var p = player.get('_player');
        if(p && p.getDuration) {
          player.set('duration', Math.round(p.getDuration()));
        }
        if(p && p.getCurrentTime) {
          player.set('time', Math.round(p.getCurrentTime()));
        }
        if(p && p.getPlayerState) {
          var state = p.getPlayerState();
          if(state == window.YT.PlayerState.PLAYING) {
            player.set('paused', false);
            if(!p.started) {
              p.started = true;
              player.set('started', true);
            }
          } else {
            player.set('paused', true);
          }
        }
      }
    });
    Ember.run.later(CoughDrop.YT.poll, 100);
  }
};
Ember.run.later(CoughDrop.YT.poll, 500);

CoughDrop.boxPad = 17;
CoughDrop.borderPad = 5;
CoughDrop.labelHeight = 15;
CoughDrop.customEvents = customEvents;
CoughDrop.expired = function() {
  var keys = window.app_version.match(/(\d+)\.(\d+)\.(\d+)/);
  var version = parseInt(keys[1] + keys[2] + keys[3], 10);
  var now = parseInt(window.moment().format('YYYYMMDD'), 10);
  var diff = now - version;
  return diff > 30;
};
window.CoughDrop = CoughDrop;
window.CoughDrop.VERSION = window.app_version;

export default CoughDrop;
