/*
 * Copyright 2020 Board of Trustees of the University of Illinois.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'package:http/http.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:illinois/model/Organization.dart';
import 'package:illinois/service/Network.dart';
import 'package:illinois/service/NotificationService.dart';
import 'package:illinois/service/Service.dart';
import 'package:illinois/service/Storage.dart';
import 'package:illinois/utils/Crypt.dart';
import 'package:illinois/utils/Utils.dart';

class Organizations with Service {

  static const String _organizationsHookAsset    = 'organizations.hook.json.enc';
  static const String _organizationsAsset        = 'organizations.json.enc';

  static const String notifyOrganizationChanged  = "edu.illinois.rokwire.organizations.organization.changed";
  static const String notifyEnvironmentChanged   = "edu.illinois.rokwire.organizations.environment.changed";

  Organization       _organization;
  List<Organization> _organizations;

  // Singletone Instance

  Organizations._internal();
  static final Organizations _instance = Organizations._internal();

  factory Organizations() {
    return _instance;
  }
  
  static Organizations get instance {
    return _instance;
  }

  // Service

  @override
  Future<void> initService() async {
    _organization = Storage().organization;
    if (_organization?.id == null) {
      _organizations = await _loadOrganizations();
      if (_organizations?.length == 1) {
        Storage().organization = _organization = _organizations.first;
      }
      else if (Storage().onBoardingPassed == true) {
        Storage().organization = _organization = Organization.findInList(_organizations, isDefault: true);
      }
    }
  }

  @override
  Future<void> clearService() async {
    _organization = null;
    _organizations = null;
  }

  @override
  Set<Service> get serviceDependsOn {
    return Set.from([Storage()]);
  }

  // Implementation

  List<Organization> get organizations {
    return _organizations;
  }

  Organization get organization {
    return _organization;
  }

  Future<void> setOrganization(Organization organization, {bool notifyChanged = true}) async {
    if ((organization?.id != null) && (_organization?.id != organization.id)) {
      String environment = Storage().configEnvironment;
      List<Organization> organizations = _organizations;
      await Services().clear();
      _organizations = organizations;
      Storage().organization = organization;
      if (organization.hasEnvironment(environment)) {
        Storage().configEnvironment = environment;
      }
      await Services().init();
      if (notifyChanged == true) {
        NotificationService().notify(notifyOrganizationChanged);
      }
    }
  }

  String get environment {
    if (_organization != null) {
      String storageEnvironment = Storage().configEnvironment;
      if (_organization.hasEnvironment(storageEnvironment)) {
        return storageEnvironment;
      }
      return _organization.defaultEnvironment;
    }
    return null;
  }

  Future<void> setEnvironment(String value, {bool notifyChanged = true}) async {
    if ((_organization != null) && _organization.hasEnvironment(value) && (environment != value)) {
      Organization organization = _organization;
      List<Organization> organizations = _organizations;
      await Services().clear();
      _organizations = organizations;
      Storage().organization = organization;
      Storage().configEnvironment = (organization.defaultEnvironment != value) ? value : null;
      await Services().init();
      if (notifyChanged == true) {
        NotificationService().notify(notifyEnvironmentChanged);
      }
    }
  }

  bool get isDevEnvironment {
    return this.environment == 'dev';
  }

  bool get isTestEnvironment {
    return this.environment == 'test';
  }

  ApiHook get configApiHook {
    return _organization?.apiHook(environment: this.environment);
  }

  Future<List<Organization>> ensureOrganizations() async {
    if (_organizations == null) {
      _organizations = await _loadOrganizations();
    }
    return _organizations;
  }

  static Future<ApiHook> _loadOrganizationsHookAsset() async {
    try {
      String hookStrEnc = await rootBundle.loadString('assets/$_organizationsHookAsset');
      String hookStr = (hookStrEnc != null) ? AESCrypt.decode(hookStrEnc) : null;
      Map<String, dynamic> hookJson = AppJson.decodeMap(hookStr);
      return ApiHook.fromJson(hookJson);
    } catch (e) {
      print(e.toString());
    }
    return null;
  }

  static Future<List<Organization>> _loadOrganizationsAsset() async {
    try {
      String organizationsStrEnc = await rootBundle.loadString('assets/$_organizationsAsset');
      String organizationsStr = (organizationsStrEnc != null) ? AESCrypt.decode(organizationsStrEnc) : null;
      List<dynamic> organizationsJson = AppJson.decodeList(organizationsStr);
      return Organization.listFromJson(organizationsJson);
    } catch (e) {
      print(e.toString());
    }
    return null;
  }

  static Future<List<Organization>> _loadOrganizations() async {
    ApiHook apiHook = await _loadOrganizationsHookAsset();
    if ((apiHook != null) && (apiHook.url != null)) {
      Map<String, String> headers = (apiHook.apiKey != null) ? {
        Network.RokwireApiKey : apiHook.apiKey
      } : null;
      
      Response response = await Network().get(apiHook.url, headers: headers);
      String responseString = (response?.statusCode == 200) ? response.body : null;
      List<dynamic> responseJson = (responseString != null) ? AppJson.decodeList(responseString) : null;
      return (responseJson != null) ? Organization.listFromJson(responseJson) : null;
    }
    else {
      return await _loadOrganizationsAsset();
    }
  }
}