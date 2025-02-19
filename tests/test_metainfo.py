# -*- coding: utf-8 -*-

from unittest import TestCase

from rmt.metainfo import MetaInfo
from tests.fixtures.meta_table import meta_table


class MetaInfoTest(TestCase):
    def setUp(self) -> None:
        pass

    def tearDown(self) -> None:
        pass

    def test_metainfo(self):
        for info in meta_table:
            if not info.get("title"):
                continue
            meta_info = MetaInfo(title=info.get("title"), subtitle=info.get("subtitle"))
            target = {
                "type": meta_info.type.value,
                "cn_name": meta_info.cn_name or "",
                "en_name": meta_info.en_name or "",
                "year": meta_info.year or "",
                "part": meta_info.part or "",
                "season": meta_info.get_season_string(),
                "episode": meta_info.get_episode_string(),
                "restype": meta_info.resource_type or "",
                "pix": meta_info.resource_pix or "",
                "video_codec": meta_info.video_encode or "",
                "audio_codec": meta_info.audio_encode or ""
            }
            self.assertEqual(target, info.get("target"))
