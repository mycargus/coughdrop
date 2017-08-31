import DS from 'ember-data';
import Ember from 'ember';
import { test, moduleForModel } from 'ember-qunit';
import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { } from 'frontend/tests/helpers/ember_helper';
import CoughDrop from '../../app';

describe('Sound', function() {
  describe("filename", function() {
    it("should not error on empty value", function() {
      var sound = CoughDrop.store.createRecord('sound', {});
      expect(sound.get('filename')).toEqual('sound');
    });
    it("should return filename if found in URL path, ignoring query params", function() {
      var sound = CoughDrop.store.createRecord('sound', {url: 'http://www.sounds.com/sound.wav'});
      expect(sound.get('filename')).toEqual('sound.wav');
      sound.set('url', 'http://www.sounds.com/sound.mp3?id=1234');
      expect(sound.get('filename')).toEqual('sound.mp3');
      sound.set('url', 'http://www.sounds.com/sound.php?id=3456');
      expect(sound.get('filename')).toEqual('sound');
    });
    it("should provide readable string for data URIs", function() {
      var sound = CoughDrop.store.createRecord('sound', {url: 'data:audio/wav;abababa'});
      expect(sound.get('filename')).toEqual('embedded sound');
    });
  });
  it("should automatically check for locally-stored data-uri on load", function() {
    var sound = CoughDrop.store.createRecord('sound', {});
    sound.didLoad();
    expect(sound.get('checked_for_data_url')).toEqual(true);
  });

  describe("extension", function() {
    it('should have specs', function() {
      expect('test').toEqual('todo');
    });
  });
});
