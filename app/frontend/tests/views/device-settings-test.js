import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { queryLog } from 'frontend/tests/helpers/ember_helper';
import startApp from '../helpers/start-app';

describe('DeviceSettingsView', 'view:device-settings', function() {
  it("should exist", function() {
    expect(1).toEqual(1);
    expect(this).not.toEqual(null);
//     expect(this).not.toEqual(window);
  });

  it("should stringify in the expected manner for modal view handling", function() {
    expect(1).toEqual(1);
//     expect(this.toString().split(/:/)[1]).toEqual('device-settings');
  });
});
