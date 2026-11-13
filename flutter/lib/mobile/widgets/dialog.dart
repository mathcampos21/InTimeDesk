import '../../common/widgets/dialog.dart' show PasswordWidget;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/api_server_warning.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

void _showSuccess() {
  showToast(translate("Successful"));
}

void setTemporaryPasswordLengthDialog(
    OverlayDialogManager dialogManager) async {
  List<String> lengths = ['6', '8', '10'];
  String length = await bind.mainGetOption(key: "temporary-password-length");
  var index = lengths.indexOf(length);
  if (index < 0) index = 0;
  length = lengths[index];
  dialogManager.show((setState, close, context) {
    setLength(newValue) {
      final oldValue = length;
      if (oldValue == newValue) return;
      setState(() {
        length = newValue;
      });
      bind.mainSetOption(key: "temporary-password-length", value: newValue);
      bind.mainUpdateTemporaryPassword();
      Future.delayed(Duration(milliseconds: 200), () {
        close();
        _showSuccess();
      });
    }

    return CustomAlertDialog(
      title: Text(translate("Set one-time password length")),
      content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: lengths
              .map(
                (value) => Row(
                  children: [
                    Text(value),
                    Radio(
                        value: value, groupValue: length, onChanged: setLength),
                  ],
                ),
              )
              .toList()),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}

void showServerSettings(OverlayDialogManager dialogManager,
    void Function(VoidCallback) setState) async {
  Map<String, dynamic> options = {};
  try {
    options = jsonDecode(await bind.mainGetOptions());
  } catch (e) {
    print("Invalid server config: $e");
  }
  showServerSettingsWithValue(
      ServerConfig.fromOptions(options), dialogManager, setState);
}

void showServerSettingsWithValue(
    ServerConfig serverConfig,
    OverlayDialogManager dialogManager,
    void Function(VoidCallback)? upSetState) async {
  const labelWidth = 120.0;
  const labelSpacing = 8.0;
  var isInProgress = false;
  var isUnlocked = false;
  final idCtrl = TextEditingController(text: serverConfig.idServer);
  final relayCtrl = TextEditingController(text: serverConfig.relayServer);
  final apiCtrl = TextEditingController(text: serverConfig.apiServer);
  final keyCtrl = TextEditingController(text: serverConfig.key);

  RxString idServerMsg = ''.obs;
  RxString relayServerMsg = ''.obs;
  RxString apiServerMsg = ''.obs;

  final controllers = [idCtrl, relayCtrl, apiCtrl, keyCtrl];
  final errMsgs = [
    idServerMsg,
    relayServerMsg,
    apiServerMsg,
  ];

  dialogManager.show((setState, close, context) {
    Future<bool> submit() async {
      if (!isUnlocked) {
        showToast(translate('Unlock with master password to modify'));
        return false;
      }
      setState(() {
        isInProgress = true;
      });
      final k = ServerConfig.normalizeBase64Key(keyCtrl.text);
      keyCtrl.text = k;
      bool ret = await setServerConfig(
          null,
          errMsgs,
          ServerConfig(
              idServer: idCtrl.text.trim(),
              relayServer: relayCtrl.text.trim(),
              apiServer: apiCtrl.text.trim(),
              key: k));
      setState(() {
        isInProgress = false;
      });
      return ret;
    }

    Widget buildField(
        String label, TextEditingController controller, String errorMsg,
        {String? Function(String?)? validator,
        bool autofocus = false,
        bool obscureText = false,
        bool readOnly = false,
        Widget? suffixIcon}) {
      if (isDesktop || isWeb) {
        return Row(
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(label),
            ),
            SizedBox(width: labelSpacing),
            Expanded(
              child: serverSettingsTextFormField(
                label: label,
                controller: controller,
                errorMsg: errorMsg,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                showLabelText: false,
                validator: validator,
                autofocus: autofocus,
                obscureText: obscureText,
                readOnly: readOnly,
                suffixIcon: suffixIcon,
              ).workaroundFreezeLinuxMint(),
            ),
          ],
        );
      }

      return serverSettingsTextFormField(
        label: label,
        controller: controller,
        errorMsg: errorMsg,
        validator: validator,
        obscureText: obscureText,
        readOnly: readOnly,
        suffixIcon: suffixIcon,
      ).workaroundFreezeLinuxMint();
    }

    return CustomAlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(translate('ID/Relay Server'))),
          if (isUnlocked)
            ...ServerConfigImportExportWidgets(controllers, errMsgs),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Form(
          child: Obx(() => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildField(translate('ID Server'), idCtrl, idServerMsg.value,
                      autofocus: true, readOnly: !isUnlocked),
                  SizedBox(height: 8),
                  if (!isIOS && !isWeb) ...[
                    buildField(translate('Relay Server'), relayCtrl,
                        relayServerMsg.value, readOnly: !isUnlocked),
                    SizedBox(height: 8),
                  ],
                  buildField(
                    translate('API Server'),
                    apiCtrl,
                    apiServerMsg.value,
                    readOnly: !isUnlocked,
                    validator: (v) {
                      if (v != null && v.isNotEmpty) {
                        if (!(v.startsWith('http://') ||
                            v.startsWith("https://"))) {
                          return translate("invalid_http");
                        }
                      }
                      return null;
                    },
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: isDesktop || isWeb ? labelWidth + labelSpacing : 0,
                    ),
                    child: ApiServerWarning(
                      controller: apiCtrl,
                      idController: idCtrl,
                      message: translate('api_server_connection_tip'),
                      emptyMessage: translate('api_server_empty_tip'),
                    ),
                  ),
                  SizedBox(height: 8),
                  buildField(
                    'Key',
                    keyCtrl,
                    '',
                    obscureText: !isUnlocked,
                    readOnly: !isUnlocked,
                  ),
                  if (!isUnlocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.lock, size: 16),
                        label: Text(translate('Unlock with Master Password')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0B57D0),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        onPressed: () {
                          final pinCtrl = TextEditingController();
                          gFFI.dialogManager.show((pinSetState, pinClose, pinContext) {
                            String? pinError;
                            void closeMasterPinDialog() {
                              pinClose();
                            }
                            void tryUnlock() {
                              if (isMasterPassword(pinCtrl.text.trim())) {
                                setState(() {
                                  isUnlocked = true;
                                });
                                closeMasterPinDialog();
                                showToast(translate('Settings unlocked'));
                              } else {
                                pinSetState(() {
                                  pinError = translate('Wrong PIN');
                                });
                              }
                            }
                            return CustomAlertDialog(
                              title: Text(translate('Master Password')),
                              content: PasswordWidget(
                                title: translate('Master Password'),
                                controller: pinCtrl,
                                errorText: pinError,
                                hintText: translate('Enter master password to unlock'),
                              ),
                              actions: [
                                dialogButton(translate('Cancel'), onPressed: closeMasterPinDialog, isOutline: true),
                                dialogButton(translate('OK'), onPressed: tryUnlock),
                              ],
                              onSubmit: tryUnlock,
                              onCancel: closeMasterPinDialog,
                            );
                          }).whenComplete(() => pinCtrl.dispose());
                        },
                      ),
                    ),
                  if (isInProgress)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                ],
              )),
        ),
      ),
      actions: [
        dialogButton(translate('Cancel'), onPressed: () {
          close();
        }, isOutline: true),
        dialogButton(
          translate('OK'),
          onPressed: () async {
            if (!isUnlocked) {
              close();
              return;
            }
            if (await submit()) {
              close();
              showToast(translate('Successful'));
              upSetState?.call(() {});
            } else {
              showToast(translate('Failed'));
            }
          },
        ),
      ],
    );
  }).whenComplete(() {
    for (final c in controllers) {
      c.dispose();
    }
  });
}

TextFormField serverSettingsTextFormField({
  required String label,
  required TextEditingController controller,
  required String errorMsg,
  String? Function(String?)? validator,
  bool autofocus = false,
  bool showLabelText = true,
  EdgeInsetsGeometry? contentPadding,
  bool obscureText = false,
  bool readOnly = false,
  Widget? suffixIcon,
}) {
  return TextFormField(
    controller: controller,
    obscureText: obscureText,
    readOnly: readOnly,
    decoration: InputDecoration(
      labelText: showLabelText ? label : null,
      errorText: errorMsg.isEmpty ? null : errorMsg,
      contentPadding: contentPadding,
      suffixIcon: suffixIcon,
    ),
    validator: validator,
    autofocus: autofocus,
    keyboardType: TextInputType.visiblePassword,
    textCapitalization: TextCapitalization.none,
    autocorrect: false,
    enableSuggestions: false,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    enableIMEPersonalizedLearning: false,
    spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
  );
}

void setPrivacyModeDialog(
  OverlayDialogManager dialogManager,
  List<TToggleMenu> privacyModeList,
  RxString privacyModeState,
) async {
  dialogManager.dismissAll();
  dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('Privacy mode')),
      content: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: privacyModeList
              .map((value) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: value.child,
                    value: value.value,
                    onChanged: value.onChanged,
                  ))
              .toList()),
    );
  }, backDismiss: true, clickMaskDismiss: true);
}
