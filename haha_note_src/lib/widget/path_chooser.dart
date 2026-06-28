
import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/utils.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:cloud_disk_note_app/util/form_validator.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'my_text_form_field.dart';

const _TAG = "path_chooser.dart";

class PathChooser extends StatelessWidget {
  final TextEditingController path;
  final String textFileLabel;
  final void Function(String) showMsg;
  final void Function(String) showMsgLong;
  final void Function() refreshUI;
  final bool trueDirFalseFile;
  final bool? trueExistErrFalseNoExistErrNullNoCheckExist;
  final bool errIfPathEmpty;
  final bool errIfPathNotAbsOrInvalid;
  final String? Function(String? path, FileSystemEntityType?)? errIfCallerConsideredPathInvalid;
  final bool showFileChooserButton;
  final ValueChanged<String>? onFieldSubmitted;

  const PathChooser({
    super.key,
    required this.path,
    required this.textFileLabel,
    required this.showMsg,
    required this.showMsgLong,
    required this.refreshUI,
    required this.trueDirFalseFile,
    required this.trueExistErrFalseNoExistErrNullNoCheckExist,
    required this.errIfPathEmpty,
    required this.errIfPathNotAbsOrInvalid,
    required this.errIfCallerConsideredPathInvalid,
    required this.showFileChooserButton,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: MyTextFormField(
            controller: path,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: textFileLabel,
              // 打开文件夹选择器，选择路径
              suffixIcon: showFileChooserButton ? IconButton(
                onPressed: () async {
                  try {
                    if(trueDirFalseFile) {
                      final String? directoryPath = await getDirectoryPath();
                      App.logger.debug(_TAG, "directoryPath: $directoryPath");
                      if (directoryPath == null) {
                        return;
                      }

                      path.text = directoryPath;
                    }else {
                      final file = await openFile();
                      if(file == null) {
                        // user canceled
                        return;
                      }

                      path.text = file.path;
                    }

                  }catch(e, st) {
                    App.logger.debug(_TAG, "choose path err: $e, st: $st");
                    showMsgLong("choose path err: $e");
                  }
                },
                icon: Icon(trueDirFalseFile ? Icons.folder_outlined : Icons.insert_drive_file_outlined)
              ) : null,
            ),
            validator: (value) {
              if(value == null) {
                return t.pleaseInput;
              }

              if(errIfPathEmpty) {
                final emptyErr = FormValidator.errIfPathEmpty(value);
                if(emptyErr != null) {
                  return emptyErr;
                }
              }


              if(errIfPathNotAbsOrInvalid) {
                final pathCheck = FormValidator.errIfPathNotAbsOrInvalid(value, isWindows: Platform.isWindows);
                if(pathCheck != null) {
                  return pathCheck;
                }
              }

              // 检查文件类型
              final fileType = getFileTypeSync(value);
              if(fileType != FileSystemEntityType.notFound &&
                  fileType != FileSystemEntityType.file &&
                  fileType != FileSystemEntityType.directory) {
                return t.invalidPath;
              }

              if(trueExistErrFalseNoExistErrNullNoCheckExist != null) {
                if(trueExistErrFalseNoExistErrNullNoCheckExist == false) {
                  // 不存在则报错
                  if(fileType == FileSystemEntityType.notFound) {
                    return t.pathDoesntExist;
                  }
                }else {
                  // 存在则报错（注意：目录若存在且空为特殊情况，不报错）
                  if(fileType != FileSystemEntityType.notFound) {
                    // 若期望选择的是文件，则只判断是否存在，若存在则报错
                    if(!trueDirFalseFile) {
                      return t.pathAlreadyExists;
                    }

                    if(fileType == FileSystemEntityType.directory) {
                      // 若期望选择的是目录且路径是目录，则判断是否存在，若存在且非空，则报错
                      if(!isDirEmptyOrNoExistsSync(value)) {
                        // 目录非空则报错
                        return t.pathAlreadyExists;
                      }
                    }else {
                      // 期望选择目录，但路径存在且不是目录，报错
                      return t.invalidPath;
                    }
                  }

                }
              }

              if(errIfCallerConsideredPathInvalid != null) {
                final result = errIfCallerConsideredPathInvalid?.call(value, fileType);
                if(result != null) {
                  return result;
                }
              }

              return null;
            },
            onFieldSubmitted: onFieldSubmitted,
          ),
        ),
      ],
    );
  }

}